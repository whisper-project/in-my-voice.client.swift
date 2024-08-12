// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import AVFAudio
import CryptoKit

final class SpeechItem {
	private struct SpeechSettings {
		let apiRoot: String = "https://api.elevenlabs.io/v1"
		let outputFormat: String = "mp3_44100_128"
		let modelId: String = "eleven_turbo_v2"
		let similarityBoost: Float = 0.5
		let stability: Float = 0.5
		let useSpeakerBoost: Bool = true
		var apiKey, voiceId, dictionaryId, dictionaryVersion: String
		var optimizeStreamingLatency: Int

		var hashValue: Int {
			get {
				var hasher = HasherFNV1a()
				hasher.combine(apiKey)
				hasher.combine(voiceId)
				hasher.combine(dictionaryId)
				hasher.combine(dictionaryVersion)
				hasher.combine(optimizeStreamingLatency)
				let val = hasher.finalize()
				return val
			}
		}

		init() {
			apiKey = PreferenceData.elevenLabsApiKey()
			voiceId = PreferenceData.elevenLabsVoiceId()
			dictionaryId = PreferenceData.elevenLabsDictionaryId()
			dictionaryVersion = PreferenceData.elevenLabsDictionaryVersion()
			optimizeStreamingLatency = PreferenceData.elevenLabsLatencyReduction()
		}
	}

	private(set) var text: String
	private(set) var settingsHash: Int? = nil
	private(set) var historyId: String? = nil
	fileprivate private(set) var audio: NSPurgeableData? = nil

	fileprivate init(_ text: String) {
		self.text = text
	}

	fileprivate init(_ text: String, hash: Int, id: String) {
		self.text = text
		settingsHash = hash
		historyId = id
	}

	fileprivate func generateSpeech(_ callback: @escaping TransportSuccessCallback) {
		let settings = SpeechSettings()
		guard !settings.apiKey.isEmpty, !settings.voiceId.isEmpty else {
			callback((.settings, "Can't generate ElevenLabs speech due to empty api key or voice id"))
			return
		}
		settingsHash = settings.hashValue
		let endpoint = "\(settings.apiRoot)/text-to-speech/\(settings.voiceId)/stream"
		let query = "?output_format=\(settings.outputFormat)&optimize_streaming_latency=\(settings.optimizeStreamingLatency)"
		var body: [String: Any] = [
			"model_id": settings.modelId,
			"text": text,
			"voice_settings": [
				"similarity_boost": settings.similarityBoost,
				"stability": settings.stability,
				"use_speaker_boost": settings.useSpeakerBoost
			]
		]
		if !settings.dictionaryId.isEmpty && !settings.dictionaryVersion.isEmpty {
			body["pronunciation_dictionary_locators"] = [
				[
					"pronunciation_dictionary_id": settings.dictionaryId,
					"version_id": settings.dictionaryVersion,
				]
			]
		}
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
				let report = "Failed to generate speech: \(String(describing: error))"
				logAnomaly(report)
				callback((.temporary, report))
				return
			}
			guard let response = response as? HTTPURLResponse else {
				let report = "Received non-HTTP response on speech generation: \(String(describing: response))"
				logAnomaly(report)
				callback((.temporary, report))
				return
			}
			if response.statusCode == 200,
			   let data = data
			{
				logger.info("Successful speech generation for '\(self.text, privacy: .public)'")
				self.audio = NSPurgeableData(data: data)
				if let id = response.value(forHTTPHeaderField: "History-Item-Id") {
					self.historyId = id
				} else {
					logAnomaly("Speech generation is missing history item ID: \(response.allHeaderFields)")
				}
				callback(nil)
				return
			}
			logAnomaly("Speech generation of \(self.text) got response status \(response.statusCode)")
			guard let data = data,
				  let body = try? JSONSerialization.jsonObject(with: data),
				  let obj = body as? [String:Any] else {
				logAnomaly("Can't deserialize speech generation response body: \(String(describing: data))")
				return
			}
			logAnomaly("Error details of speech generation: \(obj)")
			if response.statusCode == 401 {
				callback((.settings, "Invalid ElevenLabs API key"))
			} else if let detail = obj["detail"] as? [String: String],
					  let status = detail["status"],
					  let message = detail["message"]
			{
				if status == "voice_not_found" {
					callback((.settings, "Invalid ElevenLabs voice ID"))
				} else if status == "pronunciation_dictionary_not_found" {
					callback((.settings, "Invalid ElevenLabs dictionary ID or version"))
				} else {
					callback((.report, "ElevenLabs reported a problem: \(message)"))
				}
			} else {
				callback((.report, "ElevenLabs reported a mysterious problem: \(String(describing: obj))"))
			}
		}
		logger.info("Posting generation request for '\(self.text)' to ElevenLabs")
		task.resume()
	}

	static fileprivate func isEnabled() -> Bool {
		return !PreferenceData.elevenLabsApiKey().isEmpty && !PreferenceData.elevenLabsVoiceId().isEmpty
	}

	fileprivate func downloadSpeech(_ callback: @escaping TransportSuccessCallback) {
		let settings = SpeechSettings()
		guard !settings.apiKey.isEmpty else {
			callback((.settings, "Can't download ElevenLabs speech due to empty api key"))
			return
		}
		guard let hash = self.settingsHash,
			  hash == settings.hashValue,
			  let id = self.historyId
		else {
			// need to regenerate because voice settings have changed or history ID is missing
			generateSpeech(callback)
			return
		}
		let endpoint = "\(settings.apiRoot)/history/\(id)/audio"
		var request = URLRequest(url: URL(string: endpoint)!)
		request.httpMethod = "GET"
		request.setValue(settings.apiKey, forHTTPHeaderField: "xi-api-key")
		let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
			guard error == nil else {
				let report = "Failed to retrieve speech: \(String(describing: error))"
				logAnomaly(report)
				callback((.temporary, report))
				return
			}
			guard let response = response as? HTTPURLResponse else {
				let report = "Received non-HTTP response on speech retrieval of item \(id): \(String(describing: response))"
				logAnomaly(report)
				callback((.temporary, report))
				return
			}
			if response.statusCode == 200,
			   let data = data
			{
				logger.info("Successful speech retrieval for item \(id, privacy: .public)")
				self.audio = NSPurgeableData(data: data)
				callback(nil)
				return
			}
			logAnomaly("Speech retrieval of history item \(id) got response status \(response.statusCode)")
			guard let data = data,
				  let body = try? JSONSerialization.jsonObject(with: data),
				  let obj = body as? [String:Any] else {
				logAnomaly("Can't deserialize speech retrieval response body: \(String(describing: data))")
				return
			}
			logAnomaly("Error details of speech generation: \(obj)")
			if response.statusCode == 401 {
				callback((.settings, "Invalid ElevenLabs API key"))
			} else if let detail = obj["detail"] as? [String: String],
					  let status = detail["status"],
					  let message = detail["message"]
			{
				if status == "invalid_uid" {
					callback((.report, "ElevenLabs history item not found"))
				} else {
					callback((.report, "ElevenLabs reported a problem: \(message)"))
				}
			} else {
				callback((.report, "ElevenLabs reported a mysterious problem: \(String(describing: obj))"))
			}
		}
		logger.info("Posting retrieval request for item \(id) to ElevenLabs")
		task.resume()
	}
}

final class ElevenLabs: NSObject, AVAudioPlayerDelegate {
	static let shared = ElevenLabs()

	private typealias GeneratedItem = (item: SpeechItem, audio: Data)

	private var pastItems: [String: SpeechItem] = [:]
	private var pendingItems: [GeneratedItem] = []
	private var errorCallback: TransportErrorCallback?
	private var speaker: AVAudioPlayer?
	private var emptyTextCount: Int = 0

	private static let synthesizer = AVSpeechSynthesizer()

	private func keyText(_ text: String) -> String {
		let trim = text.trimmingCharacters(in: .whitespacesAndNewlines)
		let lower = trim.lowercased()
		let key = lower.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
		return key
	}

	static func isEnabled() -> Bool {
		return SpeechItem.isEnabled()
	}

	func lookupText(_ text: String) -> SpeechItem? {
		return pastItems[keyText(text)]
	}

	func memoizeText(_ text: String, hash: Int, id: String) {
		pastItems[keyText(text)] = SpeechItem(text, hash: hash, id: id)
	}

	func forgetText(_ text: String) {
		pastItems.removeValue(forKey: keyText(text))
	}

	func speakText(text: String, errorCallback: TransportErrorCallback? = nil) {
		speakText(text: text, successCallback: { result in
			if let (severity, message) = result {
				errorCallback?(severity, message)
			}
		})
	}

	func speakText(text: String, successCallback: @escaping TransportSuccessCallback) {
		guard SpeechItem.isEnabled() else {
			fallback(text)
			successCallback(nil)
			return
		}
		errorCallback = { severity, message in
			successCallback((severity, message))
		}
		guard !text.isEmpty else {
			emptyTextCount += 1
			if emptyTextCount == 2 {
				abortCurrentSpeech()
				emptyTextCount = 0
			}
			return
		}
		emptyTextCount = 0
		if let existing = pastItems[keyText(text)] {
			if let audio = existing.audio, audio.beginContentAccess() {
				successCallback(nil)
				self.queueSpeech((existing, Data(audio)))
				audio.endContentAccess()
			} else {
				existing.downloadSpeech() { error in
					if error != nil {
						self.fallback(text)
					} else if let audio = existing.audio, audio.beginContentAccess() {
						self.queueSpeech((existing, Data(audio)))
						audio.endContentAccess()
					} else {
						logAnomaly("Downloaded audio was purged before it could be played")
						self.fallback(text)
					}
					successCallback(error)
				}
			}
		} else {
			let item = SpeechItem(text)
			item.generateSpeech() { error in
				if error != nil {
					self.fallback(text)
				} else if let audio = item.audio, audio.beginContentAccess() {
					self.pastItems[self.keyText(text)] = item
					self.queueSpeech((item, Data(audio)))
					audio.endContentAccess()
				} else {
					logAnomaly("Generated audio was purged before it could be played")
					self.fallback(text)
				}
				successCallback(error)
			}
		}
	}

	private func fallback(_ text: String) {
		// fallback to Apple speech generation
		DispatchQueue.main.async {
			let utterance = AVSpeechUtterance(string: text)
			Self.synthesizer.speak(utterance)
		}
	}

	private func queueSpeech(_ item: GeneratedItem) {
		guard !item.audio.isEmpty else {
			logAnomaly("No audio in Generated Item: \(item.item)")
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
					logAnomaly("Couldn't play speech for item \(item.item)")
				}
			}
		}
		catch {
			logAnomaly("Couldn't create player for speech: \(error)")
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

	@MainActor
	func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully: Bool) {
		if !successfully {
			logger.warning("Generated speech did not play successfully")
		}
		playNextSpeech()
	}

	func abortCurrentSpeech() {
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
