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
    
    var lostRemoteSubject: PassthroughSubject<Remote, Never> = .init()
	var contentSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()
	var controlSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()

    func start(failureCallback: @escaping (String) -> Void) {
        logger.log("Starting TCP listen transport")
        self.failureCallback = failureCallback
		self.authenticator = TcpAuthenticator(mode: .listen,
											  conversationId: conversation.id,
											  conversationName: conversation.name,
											  callback: receiveAuthError)
        openControlChannel()
    }
    
    func stop() {
        logger.info("Stopping TCP listen transport")
        closeChannels()
    }
    
    func goToBackground() {
    }
    
    func goToForeground() {
    }
    
    func sendControl(remote: Remote, chunk: WhisperProtocol.ProtocolChunk) {
        guard let target = remotes[remote.id] else {
			logAnomaly(message: "Ignoring request to send chunk to an unknown remote: \(remote.id)", kind: .global)
            return
        }
		logger.notice("Sending control packet to \(remote.kind) remote: \(remote.id, privacy: .public): \(chunk, privacy: .public)")
		logControlChunk(sentOrReceived: "sent", chunk: chunk)
		sendControlInternal(id: target.id, data: chunk.toString())
    }
    
    func drop(remote: Remote) {
        guard remotes[remote.id] != nil else {
            fatalError("Ignoring request to drop an unknown remote: \(remote.id)")
        }
		removeCandidate(remote, sendDrop: true)
    }
    
	func subscribe(remote: Remote, conversation: ListenConversation) {
        guard let remote = remotes[remote.id] else {
            logAnomaly(message: "Ignoring request to subscribe to an unknown remote: \(remote.id)", kind: .global)
            return
        }
		if whisperer === remote {
			logAnomaly(message: "Ignoring duplicate subscribe", kind: .global)
			return
		} else if let w = whisperer {
			fatalError("Got subscribe request to \(remote.id) but already subscribed to \(w.id)")
		}
		guard self.conversation == conversation else {
			fatalError("Can't subscribe to \(conversation.id): initialized with \(self.conversation.id)")
		}
        whisperer = remote
		openContentChannel(remote: remote)
		for remote in Array(remotes.values) {
			if remote !== whisperer {
				drop(remote: remote)
			}
		}
    }
    
    // MARK: Internal types, properties, and initialization
    final class Whisperer: TransportRemote {
        let id: String
		let kind: TransportKind = .global

		fileprivate var contentId = ""

        fileprivate init(id: String) {
            self.id = id
        }
    }
    
    private var failureCallback: ((String) -> Void)?
    private var clientId: String
    private var conversation: ListenConversation
    private var authenticator: TcpAuthenticator!
    private var client: ARTRealtime?
    private var channelName: String
    private var contentChannel: ARTRealtimeChannel?
    private var controlChannel: ARTRealtimeChannel?
    private var remotes: [String:Remote] = [:]
    private var whisperer: Remote?

    init(_ conversation: ListenConversation) {
        self.clientId = PreferenceData.clientId
        self.conversation = conversation
		self.channelName = conversation.id
    }
    
    //MARK: Internal methods
    private func receiveErrorInfo(_ error: ARTErrorInfo?) {
        if let error = error {
			logAnomaly(message: "TCP Listener: \(error.message)", kind: .global)
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
        let client = self.authenticator.getClient()
        client.connection.on(.connected) { _ in
            logger.log("TCP listen transport realtime client has connected")
        }
        client.connection.on(.disconnected) { _ in
            logger.log("TCP listen transport realtime client has disconnected")
        }
        return client
    }
    
	private func openContentChannel(remote: Remote) {
		guard !remote.contentId.isEmpty else {
			fatalError("Can't subscribe to remote with no content ID: \(remote)")
		}
		let channel = getClient().channels.get(channelName + ":" + remote.contentId)
		contentChannel = channel
		channel.on(monitorChannelState("content"))
		channel.subscribe(receiveContentMessage)
    }
    
	private func openControlChannel() {
		let channel = getClient().channels.get(conversation.id + ":control")
		controlChannel = channel
		channel.on(monitorChannelState("control"))
		channel.once(ARTChannelEvent.attached) { _ in
			let chunk = WhisperProtocol.ProtocolChunk.listenOffer(self.conversation)
			logger.info("TCP listen transport: sending listen offer: \(chunk)")
			self.sendControlInternal(id: "whisperer", data: chunk.toString())
			logControlChunk(sentOrReceived: "sent", chunk: chunk)
		}
		channel.subscribe(receiveControlMessage)
	}

	private func monitorChannelState(_ channel: String) -> (_ change: ARTChannelStateChange) -> Void {
		return { change in
			switch change.event {
			case .attached:
				if (change.resumed) {
					logAnomaly(message: "Listen \(channel) channel attached with continuity", kind: .global)
				} else {
					logAnomaly(message: "Listen \(channel) channel attached without continuity", kind: .global)
				}
			case .suspended:
				logAnomaly(message: "Listen \(channel) channel suspended", kind: .global)
			case .failed:
				if let code = change.reason?.code, let message = change.reason?.message {
					logAnomaly(message: "Listen \(channel) channel failed (code \(code)): \(message)", kind: .global)
				} else {
					logAnomaly(message: "Listen \(channel) channel failed for unknown reasons", kind: .global)
				}
			case .update:
				if (!change.resumed) {
					logAnomaly(message: "Listen \(channel) channel lost continuity", kind: .global)
				}
			default:
				break
			}
		}
	}

    private func closeChannels() {
		guard let control = controlChannel else {
			// we never opened the channels, so don't try to close them
			return
		}
		logger.info("TCP listen transport: closing both channels")
		logger.info("TCP listen transport: publishing drop to \(self.remotes.count) remotes")
		let chunk = WhisperProtocol.ProtocolChunk.dropping()
        control.publish("whisperer", data: chunk.toString(), callback: receiveErrorInfo)
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

	private func removeCandidate(_ remote: Remote, sendDrop: Bool = false) {
		logger.log("Removing \(remote.kind) remote \(remote.id) \(sendDrop ? "with" : "without") drop message")
		if sendDrop {
				let chunk = WhisperProtocol.ProtocolChunk.dropping()
				sendControl(remote: remote, chunk: chunk)
		}
		remotes.removeValue(forKey: remote.id)
	}

	func receiveContentMessage(message: ARTMessage) {
		let topic = message.name ?? "unknown"
		guard topic == "all" || topic == PreferenceData.clientId else {
			logger.debug("Ignoring content message meant for \(topic, privacy: .public): \(String(describing: message.data), privacy: .public)")
			return
		}
		guard let remote = remoteFor(message.clientId) else {
			logAnomaly(message: "Ignoring a message with a missing client id: \(message)", kind: .global)
			return
		}
		guard let payload = message.data as? String,
			  let chunk = WhisperProtocol.ProtocolChunk.fromString(payload) else {
			logAnomaly(message: "Ignoring a message with a non-chunk payload: \(message)", kind: .global)
			return
		}
		contentSubject.send((remote: remote, chunk: chunk))
	}

    func receiveControlMessage(message: ARTMessage) {
		let topic = message.name ?? "unknown"
		guard topic == "all" || topic == PreferenceData.clientId else {
			logger.debug("Ignoring control message meant for \(topic, privacy: .public): \(String(describing: message.data), privacy: .public)")
			return
		}
		guard let remote = remoteFor(message.clientId) else {
			logAnomaly(message: "Ignoring a message with a missing client id: \(message)", kind: .global)
			return
		}
        guard let payload = message.data as? String,
              let chunk = WhisperProtocol.ProtocolChunk.fromString(payload) else {
			logAnomaly(message: "Ignoring a message with a non-chunk payload: \(message)", kind: .global)
            return
        }
		logControlChunk(sentOrReceived: "received", chunk: chunk)
        if chunk.isPresenceMessage() {
            guard let info = WhisperProtocol.ClientInfo.fromString(chunk.text),
                  info.clientId == message.clientId
            else {
				logAnomaly(message: "Ignoring a malformed or misdirected packet: \(chunk)", kind: .global)
                return
            }
            if let value = WhisperProtocol.ControlOffset(rawValue: chunk.offset) {
                switch value {
				case .dropping:
					logger.info("Advised of drop from \(remote.kind) remote \(remote.id)")
					removeCandidate(remote)
					lostRemoteSubject.send(remote)
					// no more processing to do on this packet
					return
                case .listenAuthYes:
					logger.info("Capturing content id from \(remote.kind) remote \(remote.id)")
					let contentId = info.contentId
					guard !contentId.isEmpty else {
						fatalError("Received an empty content id in a TCP \(value) message")
					}
					remote.contentId = contentId
                default:
					break
                }
            }
        }
		logger.notice("Received control packet from \(remote.kind, privacy: .public) remote \(remote.id, privacy: .public): \(chunk, privacy: .public)")
		logger.info("Received control packet: \(chunk)")
        controlSubject.send((remote: remote, chunk: chunk))
    }

	private func remoteFor(_ clientId: String?) -> Remote? {
		guard let clientId = clientId else {
			return nil
		}
		if let existing = remotes[clientId] {
			return existing
		}
		let remote = Whisperer(id: clientId)
		remotes[clientId] = remote
		return remote
	}
}
