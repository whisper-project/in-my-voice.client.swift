// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import AVFAudio
import Combine
import CoreBluetooth

final class WhisperViewModel: ObservableObject {
    typealias Remote = ComboFactory.Publisher.Remote
    typealias Transport = ComboFactory.Publisher
    
	final class Candidate: Identifiable, Comparable {
		private(set) var id: String
		private(set) var remote: Remote
		private(set) var info: WhisperProtocol.ClientInfo
		var isPending: Bool
		var hasJoined: Bool
		private(set) var created: Date

		init(remote: Remote, info: WhisperProtocol.ClientInfo, isPending: Bool) {
			self.id = remote.id
			self.remote = remote
			self.info = info
			self.isPending = isPending
			self.hasJoined = false
			self.created = Date.now
		}

		// compare by id
		static func == (lhs: WhisperViewModel.Candidate, rhs: WhisperViewModel.Candidate) -> Bool {
			return lhs.id == rhs.id
		}

		// sort by username then id
		static func < (lhs: WhisperViewModel.Candidate, rhs: WhisperViewModel.Candidate) -> Bool {
			if lhs.info.username == rhs.info.username {
				return lhs.id < rhs.id
			} else {
				return lhs.info.username < rhs.info.username
			}
		}
	}

    @Published var statusText: String = ""
    @Published var connectionError = false
    @Published var connectionErrorDescription: String = ""
	@Published var candidates: [String: Candidate] = [:]		// id -> Candidate
	@Published var invites: [Candidate] = []
    @Published var pastText: PastTextModel = .init(mode: .whisper)
	@Published var showStatusDetail: Bool = false
	private(set) var conversation: Conversation

    private var transport: Transport
    private var cancellables: Set<AnyCancellable> = []
    private var liveText: String = ""
    private static let synthesizer = AVSpeechSynthesizer()
    private var soundEffect: AVAudioPlayer?

	let profile = UserProfile.shared

    init(_ conversation: Conversation) {
        logger.log("Initializing WhisperView model")
		self.conversation = conversation
        self.transport = ComboFactory.shared.publisher(conversation)
        self.transport.lostRemoteSubject
            .sink { [weak self] in self?.lostRemote($0) }
            .store(in: &cancellables)
		self.transport.contentSubject
			.sink { [weak self] in self?.receiveContentChunk($0) }
			.store(in: &cancellables)
		self.transport.controlSubject
			.sink { [weak self] in self?.receiveControlChunk($0) }
			.store(in: &cancellables)
    }
    
    deinit {
        logger.log("Destroying WhisperView model")
        cancellables.cancel()
    }
    
    // MARK: View entry points
    
    func start() {
        resetText()
        refreshStatusText()
        transport.start(failureCallback: signalConnectionError)
    }
    
    func stop() {
        transport.stop()
        resetText()
        refreshStatusText()
    }
    
    /// Receive an updated live text from the view.
    /// Returns the new live text the view should display.
    func updateLiveText(old: String, new: String) -> String {
        guard old != new else {
            return liveText
        }
        let chunks = WhisperProtocol.diffLines(old: old, new: new)
        for chunk in chunks {
            if chunk.isCompleteLine() {
                pastText.addLine(liveText)
                if PreferenceData.speakWhenWhispering {
                    speak(liveText)
                }
                liveText = ""
            } else {
                liveText = WhisperProtocol.applyDiff(old: liveText, chunk: chunk)
            }
        }
        transport.publish(chunks: chunks)
        return liveText
    }
    
    /// User has submitted the live text
    func submitLiveText() -> String {
        return self.updateLiveText(old: liveText, new: liveText + "\n")
    }
    
    /// Play the alert sound to all the listeners
    func playSound() {
        let soundName = PreferenceData.alertSound
        if PreferenceData.speakWhenWhispering {
            playSoundLocally(soundName)
        }
        let chunk = WhisperProtocol.ProtocolChunk.sound(soundName)
        transport.publish(chunks: [chunk])
    }
    
    /// Send the alert sound to a specific listener
    func playSound(_ candidate: Candidate) {
        guard candidates[candidate.id] != nil else {
            logger.log("Ignoring alert request for non-candidate: \(candidate.id)")
            return
        }
        let soundName = PreferenceData.alertSound
        let chunk = WhisperProtocol.ProtocolChunk.sound(soundName)
		transport.sendContent(remote: candidate.remote, chunks: [chunk])
    }

	func acceptInvite(_ id: String) {

	}

	func refuseInvite(_ id: String) {

	}

    /// Drop a listener from the authorized list
    func dropListener(_ candidate: Candidate) {
        guard let listener = candidates[candidate.id] else {
            logger.log("Ignoring drop request for non-candidate: \(candidate.id)")
            return
        }
        logger.notice("De-authorizing candidate \(listener.id)")
		profile.removeListenerFromWhisperConversation(profileId: candidate.info.profileId, conversation: conversation)
		let chunk = WhisperProtocol.ProtocolChunk.listenAuthNo(conversation)
		transport.sendControl(remote: candidate.remote, chunk: chunk)
		transport.drop(remote: candidate.remote)
    }

	func listeners() -> [Candidate] {
		candidates.values.filter{$0.hasJoined}.sorted()
	}

    func wentToBackground() {
        transport.goToBackground()
    }
    
    func wentToForeground() {
        transport.goToForeground()
    }
    
    // MARK: Internal helpers
    private func resetText() {
        self.pastText.clearLines()
        self.liveText = ""
    }
    
    private func signalConnectionError(_ reason: String) {
        Task { @MainActor in
            connectionError = true
            connectionErrorDescription = reason
        }
    }
    
    private func lostRemote(_ remote: Remote) {
		guard let removed = candidates.removeValue(forKey: remote.id) else {
			logger.info("Ignoring dropped non-candidate \(remote.id)")
			return
		}
		logger.info("Dropped listener \(removed.id)")
        refreshStatusText()
    }

	private func receiveContentChunk(_ pair: (remote: Remote, chunk: WhisperProtocol.ProtocolChunk)) {
		fatalError("Whisperer received content (\(pair.chunk.toString())) from \(pair.remote.id)")
	}

	private func receiveControlChunk(_ pair: (remote: Remote, chunk: WhisperProtocol.ProtocolChunk)) {
		processControlChunk(remote: pair.remote, chunk: pair.chunk)
	}

	private func processControlChunk(remote: Remote, chunk: WhisperProtocol.ProtocolChunk) {
		guard let candidate = candidates[remote.id] else {
			logger.warning("Ignoring control chunk (\(chunk.toString())) from unknown remote \(remote.id)")
			return
		}
		if chunk.isPresenceMessage() {
			guard let info = WhisperProtocol.ClientInfo.fromString(chunk.text) else {
				fatalError("Received a presence message with invalid data: \(chunk)")
			}
			guard info.conversationId == "discover" || info.conversationId == conversation.id else {
				logger.error("Ignoring a presence message about the wrong conversation: \(info.conversationId)")
				return
			}
			switch WhisperProtocol.ControlOffset(rawValue: chunk.offset) {
			case .listenOffer, .listenRequest:
				let candidate = candidateFor(remote: remote, info: info)
				if candidate.isPending {
					invites = candidates.values.filter{$0.isPending}.sorted()
					showStatusDetail = true
				} else {
					let chunk = WhisperProtocol.ProtocolChunk.listenAuthYes(conversation)
					transport.sendControl(remote: candidate.remote, chunk: chunk)
				}
			case .joining:
				let candidate = candidateFor(remote: remote, info: info)
				candidate.hasJoined = true
				refreshStatusText()
			default:
				fatalError("Listener received an unexpected presence message: \(chunk)")
			}
		} else if chunk.isReplayRequest() {
			guard !candidate.isPending else {
				logger.warning("Ignoring replay request from unauthorized candidate \(candidate.id)")
				return
			}
			let chunks = [WhisperProtocol.ProtocolChunk.fromLiveText(text: liveText)]
			transport.sendContent(remote: candidate.remote, chunks: chunks)
		}
	}

	private func candidateFor(
		remote: Remote,
		info: WhisperProtocol.ClientInfo
	) -> Candidate {
		if let existing = candidates[remote.id] {
			return existing
		}
		let authorized = profile.isListenerToWhisperConversation(info: info, conversation: conversation)
		let candidate = Candidate(remote: remote, info: info, isPending: !authorized)
		candidates[candidate.id] = candidate
		return candidate
	}

    // speak a set of words
    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        Self.synthesizer.speak(utterance)
    }
    
    // play the alert sound locally
    private func playSoundLocally(_ name: String) {
        var name = name
        var path = Bundle.main.path(forResource: name, ofType: "caf")
        if path == nil {
            // try again with default sound
            name = PreferenceData.alertSound
            path = Bundle.main.path(forResource: name, ofType: "caf")
        }
        guard path != nil else {
            logger.error("Couldn't find sound file for '\(name)'")
            return
        }
        let url = URL(fileURLWithPath: path!)
        soundEffect = try? AVAudioPlayer(contentsOf: url)
        if let player = soundEffect {
            if !player.play() {
                logger.error("Couldn't play sound '\(name)'")
            }
        } else {
            logger.error("Couldn't create player for sound '\(name)'")
        }
    }

    private func refreshStatusText() {
		let listeners = candidates.values.filter{$0.hasJoined}
		if listeners.isEmpty {
			if invites.isEmpty {
				statusText = "No listeners yet, but you can type"
			} else {
				statusText = "Tap to see pending listeners"
			}
		} else if listeners.count == 1 {
			if invites.isEmpty {
				statusText = "Whispering to \(listeners.first!.info.username)"
			} else {
				statusText = "Whispering to \(listeners.first!.info.username) (+ \(invites.count) pending)"
			}
        } else {
			if invites.isEmpty {
				statusText = "Whispering to \(candidates.count) listeners"
			} else {
				statusText = "Whispering to \(candidates.count) listeners (+ \(invites.count) pending)"
			}
        }
    }
}
