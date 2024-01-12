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
    
    var lostRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var contentSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()
    var controlSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()

    func start(failureCallback: @escaping (String) -> Void) {
        logger.log("Starting TCP whisper transport")
        self.failureCallback = failureCallback
        self.authenticator = TcpAuthenticator(mode: .whisper, conversationId: conversation.id, callback: receiveAuthError)
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
    
    func sendControl(remote: Remote, chunk: WhisperProtocol.ProtocolChunk) {
        guard let remote = listeners[remote.id] else {
            logger.error("Ignoring request to send chunk to a non-listener: \(remote.id)")
            return
        }
		controlChannel?.publish(remote.id, data: chunk.toString(), callback: receiveErrorInfo)
    }

    func drop(remote: Remote) {
        guard let remote = listeners[remote.id] else {
            logger.error("Ignoring request to drop a non-listener: \(remote.id)")
            return
        }
        logger.info("Dropping listener \(remote.id)")
        let chunk = WhisperProtocol.ProtocolChunk.listenAuthNo(conversation)
        controlChannel?.publish(remote.id, data: chunk.toString(), callback: receiveErrorInfo)
        droppedListeners.insert(remote.id)
    }

	func authorize(remote: Listener) {
		remote.isAuthorized = true
	}

	func deauthorize(remote: Listener) {
		remote.isAuthorized = false
	}

	func sendContent(remote: Remote, chunks: [WhisperProtocol.ProtocolChunk]) {
		guard let remote = listeners[remote.id] else {
			logger.error("Ignoring request to send chunk to a non-listener: \(remote.id)")
			return
		}
		for chunk in chunks {
			contentChannel?.publish(remote.id, data: chunk.toString(), callback: receiveErrorInfo)
		}
	}

    func publish(chunks: [WhisperProtocol.ProtocolChunk]) {
        guard !listeners.isEmpty else {
            // no one to publish to
            return
        }
        for chunk in chunks {
            contentChannel?.publish("all", data: chunk.toString(), callback: receiveErrorInfo)
        }
    }
    
    // MARK: Internal types, properties, and initialization
    final class Listener: TransportRemote {
        let id: String
		let kind: TransportKind = .global

		fileprivate var isAuthorized: Bool = false

        init(id: String) {
            self.id = id
        }
    }
    
    private var failureCallback: ((String) -> Void)?
    private var clientId: String
    private var conversation: Conversation
    private var contentChannelId: String
    private var authenticator: TcpAuthenticator!
    private var client: ARTRealtime?
    private var contentChannel: ARTRealtimeChannel?
    private var controlChannel: ARTRealtimeChannel?
    private var listeners: [String:Remote] = [:]
    private var droppedListeners: Set<String> = []

    init(_ c: Conversation) {
        self.clientId = PreferenceData.clientId
        self.conversation = c
        self.contentChannelId = UUID().uuidString
        logger.info("Content channel ID for conversation \(c.id) is \(self.contentChannelId)")
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
        contentChannel = client?.channels.get(conversation.id + ":" + contentChannelId)
        contentChannel?.on(.attached) { stateChange in
            logger.log("TCP whisper transport realtime client has attached the content channel")
        }
        contentChannel?.on(.detached) { stateChange in
            logger.log("TCP whisper transport realtime client has detached the content channel")
        }
        contentChannel?.on(.suspended) { stateChange in
            logger.warning("TCP whisper transport realtime client: the content channel is suspended")
        }
        contentChannel?.on(.failed) { stateChange in
            logger.error("TCP whisper transport realtime client: there is a content channel failure")
        }
        contentChannel?.attach()
        controlChannel = client?.channels.get(conversation.id + ":control")
        controlChannel?.on(.attached) { stateChange in
            logger.log("TCP whisper transport realtime client has attached the control channel")
        }
        controlChannel?.on(.detached) { stateChange in
            logger.log("TCP whisper transport realtime client has detached the control channel")
        }
        controlChannel?.on(.suspended) { stateChange in
            logger.warning("TCP whisper transport realtime client: the control channel is suspended")
        }
        controlChannel?.on(.failed) { stateChange in
            logger.error("TCP whisper transport realtime client: there is a control channel failure")
        }
        controlChannel?.attach()
        controlChannel?.subscribe("whisperer", callback: receiveControlMessage)
        let chunk = WhisperProtocol.ProtocolChunk.whisperOffer(conversation)
        controlChannel?.publish("all", data: chunk.toString(), callback: receiveErrorInfo)
    }
    
    private func closeChannels() {
        let chunk = WhisperProtocol.ProtocolChunk.dropping()
        controlChannel?.publish("all", data: chunk.toString(), callback: receiveErrorInfo)
        contentChannel?.detach()
        contentChannel = nil
        controlChannel?.detach()
        controlChannel = nil
        client?.close()
        client = nil
    }
    
    private func receiveControlMessage(message: ARTMessage) {
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
                  info.clientId == message.clientId
            else {
                logger.error("Ignoring a malformed or misdirected invite: \(chunk.text))")
                return
            }
            if let value = WhisperProtocol.ControlOffset(rawValue: chunk.offset) {
                logger.info("Received \(value) message from \(info.clientId) profile \(info.profileId) (\(info.username))")
                switch value {
                case .listenOffer, .listenRequest, .joining:
                    if listeners[info.clientId] == nil {
                        logger.info("Adding listener from \(value) message")
                        let remote = Remote(id: info.clientId)
                        listeners[info.clientId] = remote
                    }
                case .dropping:
                    if let existing = listeners.removeValue(forKey: info.clientId) {
                       logger.info("Dropping listener from \(value) message")
                       lostRemoteSubject.send(existing)
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
        guard let sender = message.clientId,
              let remote = listeners[sender] else {
            logger.error("Ignoring a message from an unknown sender: \(String(describing: message))")
            return
        }
        controlSubject.send((remote: remote, chunk: chunk))
    }
}
