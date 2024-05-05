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
		self.authenticator = TcpAuthenticator(mode: .whisper,
											  conversationId: conversation.id,
											  conversationName: conversation.name,
											  callback: receiveAuthError)
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
        guard let remote = remotes[remote.id] else {
            logAnomaly(message: "Ignoring request to send chunk to an unknown remote: \(remote.id)", kind: .global)
            return
        }
		logger.info("Sending control packet to \(remote.kind) remote: \(remote.id): \(chunk)")
		sendControlInternal(id: remote.id, data: chunk.toString())
		logControlChunk(sentOrReceived: "sent", chunk: chunk)
    }

    func drop(remote: Remote) {
        guard let remote = remotes[remote.id] else {
            fatalError("Ignoring request to drop an unknown \(remote.kind) remote: \(remote.id)")
        }
        logger.info("Dropping \(remote.kind) remote \(remote.id)")
		removeRemote(remote)
    }

	func authorize(remote: Listener) {
		remote.isAuthorized = true
	}

	func deauthorize(remote: Listener) {
		remote.isAuthorized = false
	}

	func sendContent(remote: Remote, chunks: [WhisperProtocol.ProtocolChunk]) {
		guard let remote = remotes[remote.id] else {
			logAnomaly(message: "Ignoring request to send chunk to an unknown remote: \(remote.id)", kind: .global)
			return
		}
		for chunk in chunks {
			contentChannel?.publish(remote.id, data: chunk.toString(), callback: receiveErrorInfo)
		}
	}

    func publish(chunks: [WhisperProtocol.ProtocolChunk]) {
        guard !remotes.isEmpty else {
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
		fileprivate var hasDropped: Bool = false

		init(id: String) {
            self.id = id
        }
    }
    
    private var failureCallback: ((String) -> Void)?
    private var clientId: String
    private var conversation: WhisperConversation
    private var authenticator: TcpAuthenticator!
    private var client: ARTRealtime?
    private var contentChannel: ARTRealtimeChannel?
    private var controlChannel: ARTRealtimeChannel?
    private var remotes: [String:Remote] = [:]
	private var isRestart = false

    init(_ c: WhisperConversation) {
        self.clientId = PreferenceData.clientId
        self.conversation = c
    }
    
    //MARK: Internal methods
    private func receiveErrorInfo(_ error: ARTErrorInfo?) {
        if let error = error {
			logAnomaly(message: "TCP send/receive error: \(error.message)", kind: .global)
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
        client!.connection.on(.connected) { _ in
            logger.log("TCP whisper transport realtime client has connected")
        }
        client!.connection.on(.disconnected) { _ in
            logger.log("TCP whisper transport realtime client has disconnected")
        }
		openContentChannel()
        openControlChannel()
    }

	private func openContentChannel() {
		let channel = client!.channels.get(conversation.id + ":" + PreferenceData.contentId)
		contentChannel = channel
	}

	private func openControlChannel() {
		let channel = client!.channels.get(conversation.id + ":control")
		controlChannel = channel
		channel.on(monitorControlChannelState)
		// try a transient send on the channel to see if we trigger an error and need to restart
		channel.publish("noone", data: "test data") { error in
			if let error = error {
				logAnomaly(message: "Control channel first send error: \(error.message)", kind: .global)
				DispatchQueue.main.async {
					self.stop()
					self.isRestart = true
					self.failureCallback!("notify-restart")
					logAnomaly(message: "Restarting whisper transport", kind: .global)
					self.start(failureCallback: self.failureCallback!)
				}
			}
		}
		channel.once(ARTChannelEvent.attached) { _ in
			if self.isRestart {
				self.isRestart = false
				let chunk = WhisperProtocol.ProtocolChunk.restart()
				logger.notice("Broadcasting restart to control channel")
				self.sendControlInternal(id: "all", data: chunk.toString())
				logControlChunk(sentOrReceived: "sent", chunk: chunk)
			}
			let chunk = WhisperProtocol.ProtocolChunk.whisperOffer(self.conversation)
			logger.notice("Broadcasting whisper offer to control channel: \(chunk, privacy: .public)")
			self.sendControlInternal(id: "all", data: chunk.toString())
			logControlChunk(sentOrReceived: "sent", chunk: chunk)
		}
		channel.subscribe(receiveControlMessage)
		channel.presence.subscribe(receivePresenceMessage)
	}

	private func monitorControlChannelState(_ change: ARTChannelStateChange) {
		switch change.event {
		case .attached:
			if (change.resumed) {
				logAnomaly(message: "Whisper control channel attached with continuity", kind: .global)
			} else {
				logAnomaly(message: "Whisper control channel attached without continuity", kind: .global)
			}
		case .suspended:
			logAnomaly(message: "Whisper control channel suspended", kind: .global)
		case .failed:
			if let code = change.reason?.code, let message = change.reason?.message {
				logAnomaly(message: "Whisper control channel failed (code \(code)): \(message)", kind: .global)
			} else {
				logAnomaly(message: "Whisper control channel failed for unknown reasons", kind: .global)
			}
		case .update:
			if (!change.resumed) {
				logAnomaly(message: "Whisper control channel lost continuity", kind: .global)
			}
		default:
			break
		}
	}

    private func closeChannels() {
		guard let control = controlChannel else {
			// we never opened the channels, so nothing to do
			return
		}
		logger.info("Send drop message to \(self.remotes.count) remotes")
        let chunk = WhisperProtocol.ProtocolChunk.dropping()
        control.publish("all", data: chunk.toString(), callback: receiveErrorInfo)
		if let content = contentChannel {
			content.detach()
			contentChannel = nil
		}
        control.detach()
        controlChannel = nil
		client = nil
		authenticator.releaseClient()
    }
    
	private func sendControlInternal(id: String, data: String) {
		controlChannel?.publish(id, data: data, callback: receiveErrorInfo)
	}

    private func receiveControlMessage(message: ARTMessage) {
		let topic = message.name ?? "unknown"
		guard topic == "whisperer" || topic == PreferenceData.clientId else {
			logger.debug("Ignoring control message meant for \(topic, privacy: .public): \(String(describing: message.data), privacy: .public)")
			return
		}
		guard let remote = listenerFor(message.clientId) else {
			logAnomaly(message: "Ignoring a message with a missing client id: \(message)", kind: .global)
			return
		}
        guard let payload = message.data as? String,
              let chunk = WhisperProtocol.ProtocolChunk.fromString(payload)
        else {
			logAnomaly(message: "Ignoring a message with a non-chunk payload: \(String(describing: message))", kind: .global)
            return
        }
		logControlChunk(sentOrReceived: "received", chunk: chunk)
		if chunk.offset == WhisperProtocol.ControlOffset.dropping.rawValue {
			logger.info("Received dropping message from \(remote.kind) remote \(remote.id)")
			remote.hasDropped = true
			removeRemote(remote)
			lostRemoteSubject.send(remote)
			return
		}
		logger.notice("Received control packet from \(remote.kind, privacy: .public) remote \(remote.id, privacy: .public): \(chunk, privacy: .public)")
        controlSubject.send((remote: remote, chunk: chunk))
    }

	private func receivePresenceMessage(message: ARTPresenceMessage) {
		// look out for web remotes which detach by closing their window
		// (in which case no drop messages are sent)
		guard message.action == .leave || message.action == .absent else {
			return
		}
		guard let clientId = message.clientId, let remote = remotes[clientId], !remote.hasDropped else {
			logger.info("Received leave presence message from an already-dropped remote")
			return
		}
		logger.info("Got leave message from a remote which hasn't dropped: \(remote.id)")
		remote.hasDropped = true
		removeRemote(remote)
		lostRemoteSubject.send(remote)
	}

	private func removeRemote(_ remote: Remote) {
		if !remote.hasDropped {
			// tell this remote we're dropping it
			let chunk = WhisperProtocol.ProtocolChunk.dropping()
			sendControl(remote: remote, chunk: chunk)
		}
		remotes.removeValue(forKey: remote.id)
	}

	private func listenerFor(_ clientId: String?) -> Remote? {
		guard let clientId = clientId else {
			return nil
		}
		if let existing = remotes[clientId] {
			return existing
		}
		let remote = Listener(id: clientId)
		remotes[clientId] = remote
		return remote
	}
}
