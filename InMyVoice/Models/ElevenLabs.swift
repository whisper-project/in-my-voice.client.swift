// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import AVFAudio
import CryptoKit

typealias SpeechCallback = (SpeechItem?) -> Void

final class ElevenLabs: NSObject, AVAudioPlayerDelegate {
	static let shared = ElevenLabs()

	static private(set) var apiKey: String = ""
	static private(set) var voiceId: String = ""

	static func isEnabled() -> Bool {
		return !Self.apiKey.isEmpty && !Self.voiceId.isEmpty
	}

	private static let fallbackSynth = AVSpeechSynthesizer()

	private typealias GeneratedItem = (item: SpeechItem, audio: Data)
	private let saveName = PreferenceData.profileRoot + "ElevenLabsSettings"
	private var pastItems: [String: SpeechItem] = [:]
	private var pendingItems: [GeneratedItem] = []
	private var callback: SpeechCallback?
	private var speaker: AVAudioPlayer?
	private var emptyTextCount: Int = 0

	override init() {
		super.init()
		loadSettings()
	}

	private func keyText(_ text: String) -> String {
		let trim = text.trimmingCharacters(in: .whitespacesAndNewlines)
		let lower = trim.lowercased()
		let key = lower.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
		return key
	}

	private func loadSettings() {
		if let data = Data.loadJsonFromDocumentsDirectory(saveName),
		   let settings = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
		   let apiKey = settings["apiKey"] as? String,
		   let voiceId = settings["voiceId"] as? String
		{
			Self.apiKey = apiKey
			Self.voiceId = voiceId
		} else {
			saveSettings()
		}
	}

	private func saveSettings() {
		let settings: [String: String] = [
			"apiKey": Self.apiKey,
			"voiceId": Self.voiceId,
		]
		guard let data = try? JSONSerialization.data(withJSONObject: settings, options: []) else {
			return
		}
		data.saveJsonToDocumentsDirectory(saveName)
	}

	func downloadSettings() {
		let dataHandler: (Data) -> Void = { data in
			if data.isEmpty {
				// server has no settings, so we shouldn't
				Self.apiKey = ""
				Self.voiceId = ""
				self.saveSettings()
			} else if let obj = try? JSONSerialization.jsonObject(with: data, options: []),
					  let settings = obj as? [String: String],
					  let apiKey = settings["apiKey"],
					  let voiceId = settings["voiceId"]
			{
				Self.apiKey = apiKey
				Self.voiceId = voiceId
				self.saveSettings()
			} else {
				let body = String(String(decoding: data, as: Unicode.UTF8.self))
				ServerProtocol.notifyAnomaly("Downloaded server speech settings were malformed: \(body)")
			}
		}
		ServerProtocol.downloadElevenLabsSettings(dataHandler)
	}

	func lookupText(_ text: String) -> SpeechItem? {
		return pastItems[keyText(text)]
	}

	func memoizeText(_ text: String, hash: String, id: String) {
		pastItems[keyText(text)] = SpeechItem(text, hash: hash, id: id)
	}

	func forgetText(_ text: String) {
		pastItems.removeValue(forKey: keyText(text))
	}

	func speakText(text: String, callback: SpeechCallback? = nil) {
		self.callback = callback
		guard !text.isEmpty else {
			emptyTextCount += 1
			if emptyTextCount == 2 {
				abortCurrentSpeech()
				emptyTextCount = 0
			}
			return
		}
		guard Self.isEnabled() else {
			fallback(text)
			self.callback?(nil)
			return
		}
		emptyTextCount = 0
		if let existing = pastItems[keyText(text)] {
			if let audio = existing.audio, audio.beginContentAccess() {
				logger.info("Successful reuse of generated speech for item \(existing.historyId, privacy: .public)")
				callback?(existing)
				self.queueSpeech((existing, Data(audio)))
				audio.endContentAccess()
			} else {
				existing.downloadSpeech() { success in
					if success == nil {
						self.fallback(text)
						self.callback?(nil)
					} else if let audio = existing.audio, audio.beginContentAccess() {
						self.queueSpeech((existing, Data(audio)))
						audio.endContentAccess()
						self.callback?(existing)
					} else {
						ServerProtocol.notifyAnomaly("Downloaded audio was purged before it could be played")
						self.fallback(text)
						self.callback?(nil)
					}
				}
			}
		} else {
			let item = SpeechItem(text)
			item.generateSpeech() { success in
				if success == nil {
					self.fallback(text)
					self.callback?(nil)
				} else if let audio = item.audio, audio.beginContentAccess() {
					self.pastItems[self.keyText(text)] = item
					self.queueSpeech((item, Data(audio)))
					audio.endContentAccess()
					self.callback?(item)
				} else {
					ServerProtocol.notifyAnomaly("Generated audio was purged before it could be played")
					self.fallback(text)
					self.callback?(nil)
				}
			}
		}
	}

	private func fallback(_ text: String) {
		// fallback to Apple speech generation
		DispatchQueue.main.async {
			let utterance = AVSpeechUtterance(string: text)
			Self.fallbackSynth.speak(utterance)
		}
	}

	private func queueSpeech(_ item: GeneratedItem) {
		guard !item.audio.isEmpty else {
			ServerProtocol.notifyAnomaly("No audio in Generated Item: \(item.item)")
			return
		}
		DispatchQueue.main.async {
			self.pendingItems.append(item)
			if self.pendingItems.count == 1 {
				// this speech is not queued behind another
				self.playFirstSpeech()
			}
		}
	}

	@MainActor
	private func playFirstSpeech() {
		guard let item = pendingItems.first else {
			// no first speech to play, nothing to do
			return
		}
		do {
			speaker = try AVAudioPlayer(data: item.audio, fileTypeHint: "mp3")
			if let player = speaker {
				player.delegate = ElevenLabs.shared
				if !player.play() {
					ServerProtocol.notifyAnomaly("Couldn't play speech for item \(item.item)")
				}
			}
		}
		catch {
			ServerProtocol.notifyAnomaly("Couldn't create player for speech: \(error)")
		}
	}

	@MainActor
	func playNextSpeech() {
		if !pendingItems.isEmpty {
			// dequeue the last speech
			pendingItems.removeFirst()
		}
		// release the audio player
		speaker = nil
		// play the new first speech
		playFirstSpeech()
	}

	func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully: Bool) {
		if !successfully {
			logger.warning("Generated speech did not play successfully")
		}
		DispatchQueue.main.async {
			self.playNextSpeech()
		}
	}

	func abortCurrentSpeech() {
		Self.fallbackSynth.stopSpeaking(at: .immediate)
		DispatchQueue.main.async {
			guard let player = self.speaker else {
				// nothing to abort
				return
			}
			player.stop()
			self.playNextSpeech()
		}
	}
}

final class SpeechItem {
	private struct SpeechSettings {
		let apiRoot: String = "https://api.elevenlabs.io/v1"
		let outputFormat: String = "mp3_44100_128"
		let modelId: String = "eleven_flash_v2"
		let similarityBoost: Float = 0.5
		let stability: Float = 0.5
		let useSpeakerBoost: Bool = true
		let optimizeStreamingLatency: Int = 1
		var apiKey: String = ElevenLabs.apiKey
		var voiceId: String = ElevenLabs.voiceId

		func stableHash() -> String {
			var hasher = HasherFNV1a()
			hasher.combine(apiKey)
			hasher.combine(voiceId)
			let val = hasher.finalize()
			return String(val, radix: 32, uppercase: false)
		}
	}

	private(set) var text: String
	private(set) var hash: String? = nil
	private(set) var historyId: String? = nil
	fileprivate private(set) var audio: NSPurgeableData? = nil

	fileprivate init(_ text: String) {
		self.text = text
	}

	fileprivate init(_ text: String, hash: String, id: String) {
		self.text = text
		self.hash = hash
		historyId = id
	}

	fileprivate func generateSpeech(_ callback: @escaping SpeechCallback) {
		let settings = SpeechSettings()
		guard !settings.apiKey.isEmpty, !settings.voiceId.isEmpty else {
			callback(nil)
			return
		}
		let endpoint = "\(settings.apiRoot)/text-to-speech/\(settings.voiceId)/stream"
		let query = "?output_format=\(settings.outputFormat)&optimize_streaming_latency=\(settings.optimizeStreamingLatency)"
		let body: [String: Any] = [
			"model_id": settings.modelId,
			"text": text,
			"voice_settings": [
				"similarity_boost": settings.similarityBoost,
				"stability": settings.stability,
				"use_speaker_boost": settings.useSpeakerBoost
			]
		]
		guard let data = try? JSONSerialization.data(withJSONObject: body) else {
			fatalError("Can't encode body for voice generation call")
		}
		var request = URLRequest(url: URL(string: endpoint + query)!)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue(settings.apiKey, forHTTPHeaderField: "xi-api-key")
		request.httpBody = data
		let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
			guard error == nil else {
				ServerProtocol.notifyAnomaly("Failed to generate speech: \(String(describing: error))")
				callback(nil)
				return
			}
			guard let response = response as? HTTPURLResponse else {
				ServerProtocol.notifyAnomaly("Received non-HTTP response on speech generation: \(String(describing: response))")
				callback(nil)
				return
			}
			if response.statusCode == 200,
			   let data = data
			{
				logger.info("Successful speech generation for '\(self.text, privacy: .public)'")
				self.audio = NSPurgeableData(data: data)
				if let id = response.value(forHTTPHeaderField: "History-Item-Id") {
					let hash = settings.stableHash()
					logger.info("Generated speech has hash \(hash, privacy: .public), ID \(id, privacy: .public)")
					self.historyId = id
					self.hash = hash
				} else {
					ServerProtocol.notifyAnomaly("Speech generation is missing history item ID: \(response.allHeaderFields)")
				}
				callback(self)
				return
			}
			ServerProtocol.notifyElevenLabsFailure(action: "generate", code: response.statusCode, data: data)
			callback(nil)
		}
		logger.info("Posting generation request for '\(self.text)' to ElevenLabs")
		task.resume()
	}

	fileprivate func downloadSpeech(_ callback: @escaping SpeechCallback) {
		let settings = SpeechSettings()
		guard !settings.apiKey.isEmpty else {
			callback(nil)
			return
		}
		guard let id = historyId, let hash = hash else {
			ServerProtocol.notifyAnomaly("Can't download with missing history settings, regenerating...")
			generateSpeech(callback)
			return
		}
		guard hash == settings.stableHash() else {
			// need to regenerate because voice settings have changed
			logger.info("Settings hash has changed on item \(self.historyId, privacy: .public) (was \(hash)), regenerating...")
			generateSpeech(callback)
			return
		}
		logger.info("Downloading generated speech for item \(id, privacy: .public)")
		let endpoint = "\(settings.apiRoot)/history/\(id)/audio"
		var request = URLRequest(url: URL(string: endpoint)!)
		request.httpMethod = "GET"
		request.setValue(settings.apiKey, forHTTPHeaderField: "xi-api-key")
		let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
			guard error == nil else {
				ServerProtocol.notifyAnomaly("Failed to download speech: \(String(describing: error))")
				callback(nil)
				return
			}
			guard let response = response as? HTTPURLResponse else {
				ServerProtocol.notifyAnomaly("Received non-HTTP response on speech retrieval of item \(id): \(String(describing: response))")
				callback(nil)
				return
			}
			if response.statusCode == 200,
			   let data = data
			{
				logger.info("Successful speech retrieval for item \(id, privacy: .public)")
				self.audio = NSPurgeableData(data: data)
				callback(self)
				return
			}
			ServerProtocol.notifyElevenLabsFailure(action: "download", code: response.statusCode, data: data)
			callback(nil)
		}
		logger.info("Posting retrieval request for item \(id, privacy: .public) to ElevenLabs")
		task.resume()
	}
}
