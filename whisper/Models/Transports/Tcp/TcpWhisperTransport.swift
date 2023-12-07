// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine
import Ably

final class TcpWhisperTransport: PublishTransport {
    // MARK: protocol properties and methods
    typealias Remote = Listener
    
    var addRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var dropRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var receivedChunkSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()
    
    func start(failureCallback: @escaping (String) -> Void) {
        logger.log("Starting TCP whisper transport")
        self.failureCallback = failureCallback
        self.authenticator = TcpAuthenticator(mode: .whisper, conversationId: clientId, callback: receiveAuthError)
        openChannels()
    }
    
    func stop() {
        logger.log("Stopping TCP whisper Transport")
        closeChannels()
    }
    
    func goToBackground() {
    }
    
    func goToForeground() {
    }
    
    func send(remote: Remote, chunks: [WhisperProtocol.ProtocolChunk]) {
        guard let remote = listeners[remote.id] else {
            logger.error("Ignoring request to send chunk to a non-listener: \(remote.id)")
            return
        }
        for chunk in chunks {
            whisperChannel?.publish(remote.id, data: chunk.toString(), callback: receiveErrorInfo)
        }
    }
    
    func drop(remote: Remote) {
        guard let remote = listeners[remote.id] else {
            logger.error("Ignoring request to drop a non-listener: \(remote.id)")
            return
        }
        logger.info("Dropping listener \(remote.name) (\(remote.id))")
        let chunk = WhisperProtocol.ProtocolChunk.refuseInvite(conversationId: conversationId)
        whisperChannel?.publish(remote.id, data: chunk.toString(), callback: receiveErrorInfo)
        droppedListeners.insert(remote.id)
    }
    
    func publish(chunks: [WhisperProtocol.ProtocolChunk]) {
        guard !listeners.isEmpty else {
            // no one to publish to
            return
        }
        for chunk in chunks {
            whisperChannel?.publish("all", data: chunk.toString(), callback: receiveErrorInfo)
        }
    }
    
    // MARK: Internal types, properties, and initialization
    final class Listener: TransportRemote {
        let id: String
        var name: String
        
        init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }
    
    private var failureCallback: ((String) -> Void)?
    private var clientId: String
    private var conversationId: String
    private var authenticator: TcpAuthenticator!
    private var client: ARTRealtime?
    private var channelName: String
    private var whisperChannel: ARTRealtimeChannel?
    private var controlChannel: ARTRealtimeChannel?
    private var listeners: [String:Remote] = [:]
    private var droppedListeners: Set<String> = []

    init(_ url: String) {
        self.clientId = PreferenceData.clientId
        if let conversationId = PreferenceData.publisherUrlToConversationId(url: url) {
            self.conversationId = conversationId
        } else {
            self.conversationId = self.clientId
        }
        self.channelName = "\(conversationId):whisper"
    }
    
    //MARK: Internal methods
    private func receiveErrorInfo(_ error: ARTErrorInfo?) {
        if let error = error {
            logger.error("TCP Send/Receive Error: \(error.message)")
            PreferenceData.tcpErrorCount += 1
        }
    }
    
    private func receiveAuthError(_ reason: String) {
        failureCallback?(reason)
        PreferenceData.authenticationErrorCount += 1
        closeChannels()
    }
    
    private func openChannels() {
        client = self.authenticator.getClient()
        client?.connection.on(.connected) { _ in
            logger.log("TCP whisper transport realtime client has connected")
        }
        client?.connection.on(.disconnected) { _ in
            logger.log("TCP whisper transport realtime client has disconnected")
        }
        whisperChannel = client?.channels.get(channelName + ":whisper")
        whisperChannel?.on(.attached) { stateChange in
            logger.log("TCP whisper transport realtime client has attached the whisper channel")
        }
        whisperChannel?.on(.detached) { stateChange in
            logger.log("TCP whisper transport realtime client has detached the whisper channel")
        }
        whisperChannel?.on(.suspended) { stateChange in
            logger.warning("TCP whisper transport realtime client: the connection is suspended")
        }
        whisperChannel?.on(.failed) { stateChange in
            logger.error("TCP whisper transport realtime client: there is a channel failure")
        }
        whisperChannel?.attach()
        controlChannel = client?.channels.get(channelName + ":control")
        controlChannel?.on(.attached) { stateChange in
            logger.log("TCP whisper transport realtime client has attached the whisper channel")
        }
        controlChannel?.on(.detached) { stateChange in
            logger.log("TCP whisper transport realtime client has detached the whisper channel")
        }
        controlChannel?.on(.suspended) { stateChange in
            logger.warning("TCP whisper transport realtime client: the connection is suspended")
        }
        controlChannel?.on(.failed) { stateChange in
            logger.error("TCP whisper transport realtime client: there is a channel failure")
        }
        controlChannel?.attach()
        controlChannel?.subscribe("whisperer", callback: receiveMessage)
        let chunk = WhisperProtocol.ProtocolChunk.sendInvite(conversationId: conversationId)
        controlChannel?.publish("all", data: chunk.toString(), callback: receiveErrorInfo)
    }
    
    private func closeChannels() {
        let chunk = WhisperProtocol.ProtocolChunk.dropping(conversationId: conversationId)
        controlChannel?.publish("all", data: chunk.toString(), callback: receiveErrorInfo)
        whisperChannel?.detach()
        whisperChannel = nil
        controlChannel?.detach()
        controlChannel = nil
        client?.close()
        client = nil
    }
    
    private func receiveMessage(message: ARTMessage) {
        guard let name = message.name, name == "whisperer" else {
            logger.error("Ignoring a message not intended for the whisperer: \(String(describing: message))")
            return
        }
        guard let payload = message.data as? String,
              let chunk = WhisperProtocol.ProtocolChunk.fromString(payload)
        else {
            logger.error("Ignoring a message with a non-chunk payload: \(String(describing: message))")
            return
        }
        if chunk.isPresenceMessage() {
            guard let info = WhisperProtocol.ClientInfo.fromString(chunk.text),
                  info.clientId == message.clientId,
                  info.conversationId == conversationId
            else {
                logger.error("Ignoring a malformed or misdirected invite: \(chunk.text))")
                return
            }
            if let value = WhisperProtocol.ControlOffset(rawValue: chunk.offset) {
                logger.info("Received \(value) message from \(info.clientId) profile \(info.profileId) (\(info.username))")
                switch value {
                case .whisperAccept, .joining:
                    if listeners[info.clientId] == nil {
                        logger.info("Adding listener from \(value) message")
                        let remote = Remote(id: info.clientId, name: info.username)
                        listeners[info.clientId] = remote
                        addRemoteSubject.send(remote)
                    }
                case .dropping:
                    if let existing = listeners.removeValue(forKey: info.clientId) {
                       logger.info("Dropping listener from \(value) message")
                       dropRemoteSubject.send(existing)
                        // no more processing to do on this packet
                        return
                    } else {
                        logger.error("Ignoring \(value) message from a non-listener: \(info.clientId)")
                    }
                default:
                    logger.error("Ignoring an unexpected \(value) message from \(info.clientId)")
                    return
                }
            }
        }
    }
    
        guard let sender = message.clientId,
              let remote = listeners[sender] else {
            logger.error("Ignoring a message from an unknown sender: \(String(describing: message))")
            return
        }
        receivedChunkSubject.send((remote: remote, chunk: chunk))
    }
}
