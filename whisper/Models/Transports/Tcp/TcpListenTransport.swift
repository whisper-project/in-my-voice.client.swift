// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine
import Ably

final class TcpListenTransport: SubscribeTransport {
    // MARK: Protocol properties and methods
    typealias Remote = Whisperer
    
    var addRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var dropRemoteSubject: PassthroughSubject<Remote, Never> = .init()
	var contentSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()
	var controlSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()

    func start(failureCallback: @escaping (String) -> Void) {
        logger.log("Starting TCP candidate transport")
        self.failureCallback = failureCallback
		self.authenticator = TcpAuthenticator(mode: .listen, conversationId: conversation.id, callback: receiveAuthError)
        openControlChannel()
        openWhisperChannel()
    }
    
    func stop() {
        logger.info("Stopping TCP listen transport")
        closeChannels()
    }
    
    func goToBackground() {
    }
    
    func goToForeground() {
    }
    
    func sendControl(remote: Remote, chunks: [WhisperProtocol.ProtocolChunk]) {
        guard let target = candidates[remote.id] else {
            logger.error("Ignoring request to send chunk to a non-candidate: \(remote.id) (\(remote.name))")
            return
        }
        guard target === whisperer else {
            logger.error("Ignoring request to send chunk to a non-whisperer: \(remote.id) (\(remote.name))")
            return
        }
        for chunk in chunks {
            whisperChannel?.publish("whisperer", data: chunk.toString(), callback: receiveErrorInfo)
        }
    }
    
    func drop(remote: Remote) {
        guard candidates[remote.id] != nil else {
            logger.error("Ignoring request to drop a non-candidate: \(remote.id)")
            return
        }
        guard remote !== whisperer else {
            // Dropping the whisperer is a mistake.
            logger.error("Ignoring request to drop the whisperer")
            return
        }
        logger.log("Dropping candidate \(remote.id) (\(remote.name))")
        candidates.removeValue(forKey: remote.id)
        dropRemoteSubject.send(remote)
    }
    
    func subscribe(remote: Remote) {
        guard let candidate = candidates[remote.id] else {
            logger.error("Ignoring request to subscribe to a non-candidate: \(remote.id) (\(remote.name))")
            return
        }
        whisperer = candidate
        for c in candidates.keys {
            if c == candidate.id {
                continue
            }
            if let removed = candidates.removeValue(forKey: c) {
                dropRemoteSubject.send(removed)
            }
        }
    }
    
    // MARK: Internal types, properties, and initialization
    final class Whisperer: TransportRemote {
        var id: String
        var name: String
		var authorized: Bool

        fileprivate init(id: String, name: String) {
            self.id = id
            self.name = name
			self.authorized = false
        }
    }
    
    private var failureCallback: ((String) -> Void)?
    private var clientId: String
    private var conversation: Conversation
    private var authenticator: TcpAuthenticator!
    private var client: ARTRealtime?
    private var channelName: String
    private var whisperChannel: ARTRealtimeChannel?
    private var controlChannel: ARTRealtimeChannel?
    private var candidates: [String:Remote] = [:]
    private var whisperer: Remote?

    init(_ conversation: Conversation) {
        self.clientId = PreferenceData.clientId
        self.conversation = conversation
        self.channelName = "\(conversation):whisper"
    }
    
    //MARK: Internal methods
    private func receiveErrorInfo(_ error: ARTErrorInfo?) {
        if let error = error {
            logger.error("TCP Listener: \(error.message)")
        }
    }
    
    private func receiveAuthError(_ reason: String) {
        failureCallback?(reason)
        closeChannels()
    }
    
    private func getClient() -> ARTRealtime {
        if let client = self.client {
            return client
        }
        client = self.authenticator.getClient()
        client!.connection.on(.connected) { _ in
            logger.log("TCP listen transport realtime client has connected")
        }
        client!.connection.on(.disconnected) { _ in
            logger.log("TCP listen transport realtime client has disconnected")
        }
        return client!
    }
    
    private func openWhisperChannel() {
        whisperChannel = getClient().channels.get(channelName + ":whisper")
        whisperChannel?.on(.attached) { stateChange in
            logger.log("TCP listen transport realtime client has attached the whisper channel")
        }
        whisperChannel?.on(.detached) { stateChange in
            logger.log("TCP listen transport realtime client has detached the whisper channel")
        }
        whisperChannel?.attach()
        whisperChannel?.subscribe(clientId, callback: receiveMessage)
        whisperChannel?.subscribe("all", callback: receiveMessage)
    }
    
    private func openControlChannel() {
        controlChannel = getClient().channels.get(channelName + ":whisper")
        controlChannel?.on(.attached) { stateChange in
            logger.log("TCP listen transport realtime client has attached the whisper channel")
        }
        controlChannel?.on(.detached) { stateChange in
            logger.log("TCP listen transport realtime client has detached the whisper channel")
        }
        controlChannel?.attach()
        controlChannel?.subscribe(clientId, callback: receiveMessage)
        controlChannel?.subscribe("whisperer", callback: receiveMessage)
        let chunk = WhisperProtocol.ProtocolChunk.whisperOffer(c: conversation)
        controlChannel?.publish("all", data: chunk.toString(), callback: receiveErrorInfo)
    }
    
    private func closeChannels() {
		let chunk = WhisperProtocol.ProtocolChunk.dropping(c: conversation)
        controlChannel?.publish("all", data: chunk.toString(), callback: receiveErrorInfo)
        whisperChannel?.detach()
        whisperChannel = nil
        controlChannel?.detach()
        controlChannel = nil
        client?.close()
        client = nil
    }
    
    func receiveMessage(message: ARTMessage) {
        guard let name = message.name,
              (name == clientId || name == "all") else {
            logger.error("Ignoring a message not intended for this client: \(String(describing: message))")
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
				  info.conversationId == conversation.id,
                  info.clientId == message.clientId
            else {
                logger.error("Ignoring a malformed or misdirected invite: \(chunk.text))")
                return
            }
            if let value = WhisperProtocol.ControlOffset(rawValue: chunk.offset) {
                logger.info("Received a \(value) message from \(info.clientId) profile \(info.profileId) (\(info.username))")
                switch value {
                case .whisperOffer, .listenAuthYes:
                    if candidates[info.clientId] == nil {
                        logger.info("Adding candidate from a \(value) message")
                        let remote = Remote(id: info.clientId, name: info.username)
                        candidates[info.clientId] = remote
                        addRemoteSubject.send(remote)
                    }
                    // packet can now be sent to listener
                case .dropping, .listenAuthNo:
                    if let existing = candidates.removeValue(forKey: info.clientId) {
                        logger.info("Dropping candidate from a \(value) message")
                        dropRemoteSubject.send(existing)
                    } else {
                        logger.error("Ignoring a \(value) message from a non-candidate: \(info.clientId)")
                    }
                    // no more processing to do on this packet
                    return
                default:
                    logger.error("Ignoring an unexpected \(value) message from \(info.clientId)")
                    return
                }
            }
        }
        guard let sender = message.clientId,
              let remote = candidates[sender] else {
            logger.error("Ignoring a message from an unknown sender: \(String(describing: message))")
            return
        }
        contentSubject.send((remote: remote, chunk: chunk))
    }
}
