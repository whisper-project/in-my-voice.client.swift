// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import AVFAudio
import Combine
import CoreBluetooth

final class WhisperViewModel: ObservableObject {
    @Published var pastText: PastTextModel = .init()

	var interjectionPrefixOverride: String?

    private var liveText: String = ""
	private var liveTextChangeCount: Int = 0
	private var liveTextStartTime: Date?
	private var liveTextDurationMs: Int?
	private var lastLiveText: String = ""
	private var pendingLiveText: String = ""
	private var pendingLiveTextDurationMs: Int?
    private var soundEffect: AVAudioPlayer?
	private var typingPlayer: AVAudioPlayer?
	private var playingTypingSound = false

	let fp = FavoritesProfile.shared

    // MARK: View entry points
    
    func start() {
		logger.log("Starting WhisperView model")
    }
    
    func stop() {
		logger.log("Stopping WhisperView model")
    }

    /// Receive an updated live text from the view.
    /// Returns the new live text the view should display.
	/// Any complete lines in the new live text are treated as if they had been typed with 0 duration
    func updateLiveText(old: String, new: String) -> String {
		if liveTextStartTime == nil {
			liveTextStartTime = Date.now
			liveTextChangeCount = 1
		} else {
			liveTextChangeCount += 1
		}
		if old == new {
			return liveText
		}
		var newLines = new.split(separator: "\n", omittingEmptySubsequences: false)
		let lastLine = String(newLines.removeLast())
		for _ in newLines {
			completeLine()
		}
		return setLiveText(lastLine)
    }

    /// User has submitted the live text
    func submitLiveText() -> String {
        return updateLiveText(old: liveText, new: liveText + "\n")
    }

	/// The user has started or stopped interjecting.
	/// Returns the new live text the view should display.
	func interjectionChange(isStarting: Bool) -> String {
		if isStarting {
			pendingLiveText = liveText
			pendingLiveTextDurationMs = liveTextDurationMs
			liveTextDurationMs = nil
			liveTextStartTime = nil
			liveText = interjectionPrefixOverride ?? PreferenceData.interjectionPrefix()
			interjectionPrefixOverride = nil
			playInterjectionSound()
		} else {
			if !liveText.isEmpty && liveText != PreferenceData.interjectionPrefix() {
				_ = submitLiveText()
			}
			liveText = pendingLiveText
			liveTextDurationMs = pendingLiveTextDurationMs
			liveTextStartTime = nil
		}
		return liveText
	}

	/// Repeat a line typed by the Whisperer
	func repeatLine(_ text: String? = nil) {
		let line = text ?? lastLiveText
		pastText.addLine(line)
		if !line.trimmingCharacters(in: .whitespaces).isEmpty {
			lastLiveText = line
		}
		speak(line)
		if (text == nil) {
			// actually a repeat, not a favorite being used
			ServerProtocol.notifyRepeatLine()
		}
	}

    /// Play the alert sound to all the listeners
    func playSound() {
        let soundName = PreferenceData.alertSound
		playSoundLocally(soundName)
    }

	func playInterjectionSound() {
		let soundName = PreferenceData.interjectionAlertSound()
		if !soundName.isEmpty {
			playSoundLocally(soundName)
		}
	}

    func wentToBackground() {
		var duration = liveTextDurationMs
		if let startTime = liveTextStartTime {
			duration = (duration ?? 0) + Int((Date.now.timeIntervalSince(startTime))) * 1000
		}
		liveTextDurationMs = duration
		ServerProtocol.notifyBackground()
    }
    
    func wentToForeground() {
		ServerProtocol.notifyForeground()
		if liveTextStartTime != nil {
			liveTextStartTime = Date.now
		}
    }

    // MARK: Internal helpers
    private func resetText() {
        self.pastText.clearLines()
        self.liveText = ""
    }

	private func setLiveText(_ new: String) -> String {
		if liveTextStartTime != nil {
			// the line has already been started
			liveTextChangeCount += 1
			if new == "" {
				// they have deleted whatever text they had
				if playingTypingSound {
					stopTypingSound()
				}
			}
		} else {
			// there is no line in progress, maybe new starts one?
			if new != "" {
				startLine()
			}
		}
		liveText = new
		return liveText
	}

	private func startLine() {
		liveTextChangeCount = 1
		liveTextStartTime = Date.now
		liveTextDurationMs = nil
		maybeStartTypingSound()
	}

	private func completeLine() {
		maybeEndTypingSound()
		pastText.addLine(liveText)
		if !liveText.trimmingCharacters(in: .whitespaces).isEmpty {
			lastLiveText = liveText
		}
		speak(liveText)
		ServerProtocol.notifyChangeData(count: liveTextChangeCount, startTime: liveTextStartTime, durationMs: liveTextDurationMs)
		liveTextStartTime = nil
		liveTextDurationMs = nil
		liveTextChangeCount = 0
	}

	private func maybeStartTypingSound() {
		guard PreferenceData.hearTyping else {
			return
		}
		playingTypingSound = true
		playTypingSound(PreferenceData.typingSound)
	}

	private func maybeEndTypingSound() {
		stopTypingSound()
		guard PreferenceData.hearTyping else {
			return
		}
		if playingTypingSound {
			playTypingSound("typewriter-carriage-return")
			playingTypingSound = false
		}
	}

	private func stopTypingSound() {
		playingTypingSound = false
		if let player = typingPlayer {
			player.stop()
			typingPlayer = nil
		}
	}

	private func playTypingSound(_ name: String) {
		if let path = Bundle.main.path(forResource: name, ofType: "caf") {
			let url = URL(filePath: path)
			typingPlayer = try? AVAudioPlayer(contentsOf: url)
			if let player = typingPlayer {
				player.volume = Float(PreferenceData.typingVolume)
				if !player.play() {
					ServerProtocol.notifyAnomaly("Couldn't play \(name) sound")
					typingPlayer = nil
				}
			} else {
				ServerProtocol.notifyAnomaly("Can't create player for \(name) sound")
				typingPlayer = nil
			}
		} else {
			ServerProtocol.notifyAnomaly("Can't find \(name) sound in main bundle")
			typingPlayer = nil
		}
	}

	private func speak(_ text: String) {
		if let f = fp.lookupFavorite(text: text).first {
			f.speakText()
		} else {
			ElevenLabs.shared.speakText(text: text)
		}
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
            logger.error("Couldn't find sound file for '\(name, privacy: .public)'")
            return
        }
        let url = URL(fileURLWithPath: path!)
        soundEffect = try? AVAudioPlayer(contentsOf: url)
        if let player = soundEffect {
            if !player.play() {
                logger.error("Couldn't play sound '\(name, privacy: .public)'")
            }
        } else {
            logger.error("Couldn't create player for sound '\(name, privacy: .public)'")
        }
    }
}
