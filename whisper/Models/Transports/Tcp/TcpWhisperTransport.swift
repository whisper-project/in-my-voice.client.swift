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
            logger.error("Ignoring request to send chunk to an unknown \(remote.kind, privacy: .public) remote: \(remote.id, privacy: .public)")
            return
        }
		logger.info("Sending control packet to \(remote.kind) remote: \(remote.id): \(chunk)")
		controlChannel?.publish(remote.id, data: chunk.toString(), callback: receiveErrorInfo)
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
			logger.error("Ignoring request to send chunk to an unknown \(remote.kind, privacy: .public) remote: \(remote.id, privacy: .public)")
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
		fileprivate var lastControlPacketOffset: Int = 0

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
	private var controlQueue: [(id: String, data: String)] = []
    private var remotes: [String:Remote] = [:]

    init(_ c: WhisperConversation) {
        self.clientId = PreferenceData.clientId
        self.conversation = c
    }
    
    //MARK: Internal methods
    private func receiveErrorInfo(_ error: ARTErrorInfo?) {
        if let error = error {
			logger.error("TCP send/receive error: \(error.message, privacy: .public)")
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
		contentChannel = tryOpenChannel(channelType: "content")
        controlChannel = tryOpenChannel(channelType: "control")
		controlChannel?.subscribe(PreferenceData.clientId, callback: receiveControlMessage)
		controlChannel?.subscribe("whisperer", callback: receiveControlMessage)
		controlChannel?.presence.subscribe(receivePresenceMessage)
        let chunk = WhisperProtocol.ProtocolChunk.whisperOffer(conversation)
		logger.notice("Broadcasting whisper offer to control channel: \(chunk, privacy: .public)")
		sendControlInternal(id: "all", data: chunk.toString())
    }

	private func tryOpenChannel(channelType: String) -> ARTRealtimeChannel {
		let suffix = channelType == "control" ? "control" : PreferenceData.contentId
		let name = conversation.id + ":" + suffix
		guard let channel = client?.channels.get(name) else {
			fatalError("Can't open channel \(name)")
		}
		func receiveFirstError(_ error: ARTErrorInfo?) {
			if let error = error {
				logger.error("TCP first send Error: \(error.message, privacy: .public)")
				DispatchQueue.main.async {
					logger.error("Stopping and restarting TCP whisper transport due to initialization error")
					self.stop()
					self.start(failureCallback: self.failureCallback!)
				}
			}
		}
		func noticeChange(_ change: ARTChannelStateChange) {
			switch change.event {
			case .attaching, .attached:
				logger.notice("TCP whisper transport is attaching/has attached the \(channelType) channel")
			case .detaching, .detached:
				logger.notice("TCP whisper transport is detaching/has detached the \(channelType) channel")
			case .suspended:
				logger.notice("TCP whisper transport has suspended the \(channelType) channel")
			case .failed:
				logger.notice("TCP whisper transport has failed the \(channelType) channel")
			default:
				break
			}
		}
		channel.on(noticeChange)
		channel.attach()
		// try to send on the channel to see if we trigger an error and need to restart
		channel.publish("noone", data: "test data", callback: receiveFirstError)
		return channel
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
		// we may send control packets more than once to make sure one gets through
		// Because we don't want to interleave packets of different types, we keep a queue of the ones to send
		let suffix = controlChannelPacketRepeatCount > 1 ? " \(controlChannelPacketRepeatCount) times" : ""
		if controlQueue.isEmpty {
			logger.debug("TCP whisper transport: sending control packet\(suffix)")
			controlChannel?.publish(id, data: data, callback: receiveErrorInfo)
			if controlChannelPacketRepeatCount > 1 {
				var current = (id: id, data: data)
				controlQueue.append(current)
				var count = 1
				Timer.scheduledTimer(withTimeInterval: TimeInterval(0.05), repeats: true) { [weak self] timer in
					guard self != nil else {
						timer.invalidate()
						return
					}
					if count >= controlChannelPacketRepeatCount {
						self?.controlQueue.removeFirst()
						if let next = self?.controlQueue.first {
							logger.debug("TCP whisper transport: dequeing control packet")
							current = next
							count = 0
						} else {
							timer.invalidate()
							return
						}
					}
					self?.controlChannel?.publish(current.id, data: current.data, callback: self?.receiveErrorInfo)
					count += 1
				}
			}
		} else {
			logger.debug("TCP whisper transport: queueing control packet")
			controlQueue.append((id: id, data: data))
		}
	}

    private func receiveControlMessage(message: ARTMessage) {
		guard let remote = listenerFor(message.clientId) else {
			logger.error("Ignoring a message with a missing client id: \(message, privacy: .public)")
			return
		}
        guard let payload = message.data as? String,
              let chunk = WhisperProtocol.ProtocolChunk.fromString(payload)
        else {
			logger.error("Ignoring a message with a non-chunk payload: \(String(describing: message), privacy: .public)")
            return
        }
		guard chunk.offset != remote.lastControlPacketOffset else {
			logger.notice("Ignoring repeated packet: \(chunk, privacy: .public)")
			return
		}
		remote.lastControlPacketOffset = chunk.offset
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
