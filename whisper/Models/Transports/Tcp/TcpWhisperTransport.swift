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
    var receivedChunkSubject: PassthroughSubject<(remote: Remote, chunk: TextProtocol.ProtocolChunk), Never> = .init()
    
    func start(failureCallback: @escaping (String) -> Void) {
        logger.log("Starting TCP whisper transport")
        self.failureCallback = failureCallback
        self.authenticator = TcpAuthenticator(mode: .whisper, publisherId: clientId, callback: receiveAuthError)
        openChannel()
    }
    
    func stop() {
        logger.log("Stopping TCP whisper Transport")
        closeChannel()
    }
    
    func goToBackground() {
    }
    
    func goToForeground() {
    }
    
    func send(remote: Remote, chunks: [TextProtocol.ProtocolChunk]) {
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
        let chunk = TextProtocol.ProtocolChunk.dropRequest(id: remote.id)
        whisperChannel?.publish(remote.id, data: chunk, callback: receiveErrorInfo)
        droppedListeners.insert(remote.id)
    }
    
    func publish(chunks: [TextProtocol.ProtocolChunk]) {
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
    private var authenticator: TcpAuthenticator!
    private var client: ARTRealtime?
    private var channelName: String
    private var whisperChannel: ARTRealtimeChannel?
    private var listeners: [String:Remote] = [:]
    private var droppedListeners: Set<String> = []

    init(_ url: String) {
        self.clientId = PreferenceData.clientId
        self.channelName = "\(clientId):whisper"
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
        closeChannel()
    }
    
    private func openChannel() {
        client = self.authenticator.getClient()
        client?.connection.on(.connected) { _ in
            logger.log("TCP whisper transport realtime client has connected")
        }
        client?.connection.on(.disconnected) { _ in
            logger.log("TCP whisper transport realtime client has disconnected")
        }
        whisperChannel = client?.channels.get(channelName)
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
        whisperChannel?.subscribe(clientId, callback: receiveMessage)
        whisperChannel?.presence.subscribe(receivePresence)
        whisperChannel?.presence.enter(PreferenceData.userName())
    }
    
    private func closeChannel() {
        whisperChannel?.presence.leave(PreferenceData.userName())
        whisperChannel?.detach()
        whisperChannel = nil
        client?.close()
        client = nil
    }
    
    private func receiveMessage(message: ARTMessage) {
        guard let name = message.name, name == clientId else {
            logger.error("Ignoring a message not intended for this client: \(String(describing: message))")
            return
        }
        guard let sender = message.clientId,
              let remote = listeners[sender] else {
            logger.error("Ignoring a message from an unknown sender: \(String(describing: message))")
            return
        }
        guard let payload = message.data as? String,
              let chunk = TextProtocol.ProtocolChunk.fromString(payload)
        else {
            logger.error("Ignoring a message with a non-chunk payload: \(String(describing: message))")
            return
        }
        if chunk.isReplayRequest() {
            logger.info("Received replay request from \(sender)")
            // acknowledge the read request (always done at the transport level)
            let response = TextProtocol.ProtocolChunk.acknowledgeRead(hint: chunk.text)
            send(remote: remote, chunks: [response])
            // pass the request on to the whisperer
            receivedChunkSubject.send((remote: remote, chunk: chunk))
        } else {
            logger.error("Ignoring non-replay request from \(sender): \(payload)")
        }
    }
    
    func receivePresence(message: ARTPresenceMessage) {
        guard let remoteId = message.clientId, let name = message.data as? String else {
            logger.error("Ignoring a presence message missing client or info: \(String(describing: message))")
            return
        }
        guard remoteId != clientId else {
            logger.log("Ignoring a presence message about this client")
            return
        }
        switch message.action {
        case .present, .enter:
            guard listeners[remoteId] == nil else {
                logger.warning("Ignoring present/enter event for existing listener \(remoteId)")
                return
            }
            let remote = Remote(id: remoteId, name: name)
            listeners[remoteId] = remote
            addRemoteSubject.send(remote)
            if droppedListeners.contains(remoteId) {
                // they should not have come back!
                drop(remote: remote)
            }
        case .leave:
            guard let remote = listeners.removeValue(forKey: remoteId) else {
                logger.warning("Ignoring leave event for non-listener \(remoteId)")
                return
            }
            dropRemoteSubject.send(remote)
        case .update:
            guard let listener = listeners[remoteId] else {
                logger.warning("Ignoring update event for non-listener \(remoteId)")
                return
            }
            guard listener.name == name else {
                logger.error("Ignoring disallowed name update for \(remoteId) from \(listener.name) to \(name)")
                return
            }
        case .absent:
            logger.warning("Ignoring absent presence message for \(remoteId): \(String(describing: message))")
        @unknown default:
            logger.warning("Ignoring unknown presence message for \(remoteId): \(String(describing: message))")
        }
    }
}
