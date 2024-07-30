// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import AVFAudio

fileprivate final class SpeechItem {
	private let apiRoot: String = "https://api.elevenlabs.io/v1"
	private let outputFormat: String = "mp3_44100_128"
	private let modelId: String = "eleven_turbo_v2"
	private let similarityBoost: Float = 0.5
	private let stability: Float = 0.5
	private let useSpeakerBoost: Bool = true

	var text: String
	var historyId: String!
	var audio: NSPurgeableData!

	fileprivate init(_ text: String) {
		self.text = text
	}

	func generateSpeech(_ callback: @escaping ((TransportErrorSeverity, String)?) -> Void) {
		let apiKey = PreferenceData.elevenLabsApiKey()
		let voiceId = PreferenceData.elevenLabsVoiceId()
		let dictionaryId = PreferenceData.elevenLabsDictionaryId()
		let dictionaryVersion = PreferenceData.elevenLabsDictionaryVersion()
		let optimizeStreamingLatency = PreferenceData.elevenLabsLatencyReduction()
		guard !apiKey.isEmpty, !voiceId.isEmpty else {
			callback((.settings, "Can't generate ElevenLabs speech due to empty api key or voice id"))
			return
		}
		let endpoint = "\(apiRoot)/text-to-speech/\(voiceId)/stream"
		let query = "?output_format=\(outputFormat)&optimize_streaming_latency=\(optimizeStreamingLatency)"
		var body: [String: Any] = [
			"model_id": modelId,
			"text": text,
			"voice_settings": [
				"similarity_boost": similarityBoost,
				"stability": stability,
				"use_speaker_boost": useSpeakerBoost
			]
		]
		if !dictionaryId.isEmpty && !dictionaryVersion.isEmpty {
			body["pronunciation_dictionary_locators"] = [
				[
					"pronunciation_dictionary_id": dictionaryId,
					"version_id": dictionaryVersion,
				]
			]
		}
		guard let data = try? JSONSerialization.data(withJSONObject: body) else {
			fatalError("Can't encode body for voice generation call")
		}
		var request = URLRequest(url: URL(string: endpoint + query)!)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
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
					self.historyId = "no-history-ID"
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

	func downloadSpeech(_ callback: @escaping ((TransportErrorSeverity, String)?) -> Void) {
		let apiKey = PreferenceData.elevenLabsApiKey()
		guard !apiKey.isEmpty else {
			callback((.settings, "Can't retrieve ElevenLabs speech due to empty api key"))
			return
		}
		guard let id = self.historyId else {
			callback((.report, "Can't retrieve ElevenLabs speech due to missing history ID"))
			return
		}
		let endpoint = "\(apiRoot)/history/\(id)/audio"
		var request = URLRequest(url: URL(string: endpoint)!)
		request.httpMethod = "GET"
		request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
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
	private var errorCallback: ((TransportErrorSeverity, String) -> Void)?
	private var speaker: AVAudioPlayer?
	private var emptyTextCount: Int = 0

	private static let synthesizer = AVSpeechSynthesizer()

	func speakText(text: String, errorCallback: ((TransportErrorSeverity, String) -> Void)? = nil) {
		self.errorCallback = errorCallback
		guard !text.isEmpty else {
			emptyTextCount += 1
			if emptyTextCount == 2 {
				abortCurrentSpeech()
				emptyTextCount = 0
			}
			return
		}
		emptyTextCount = 0
		if let existing = pastItems[text] {
			if existing.audio.beginContentAccess() {
				self.queueSpeech((existing, Data(existing.audio)))
				existing.audio.endContentAccess()
				return
			}
			logAnomaly("Audio cache purged for item \(existing.historyId!)")
			existing.downloadSpeech() { error in
				if let (severity, message) = error {
					errorCallback?(severity, message)
					self.fallback(text)
				} else {
					self.queueSpeech((existing, Data(existing.audio)))
					existing.audio.endContentAccess()
					return
				}
			}
		} else {
			let item = SpeechItem(text)
			item.generateSpeech() { error in
				if let (severity, message) = error {
					errorCallback?(severity, message)
					self.fallback(text)
				} else {
					self.pastItems[text] = item
					self.queueSpeech((item, Data(item.audio)))
					item.audio.endContentAccess()
					return
				}
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
