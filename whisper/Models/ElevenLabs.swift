// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import AVFAudio

fileprivate final class GeneratedItem {
	private let apiRoot: String = "https://api.elevenlabs.io/v1"
	private let outputFormat: String = "mp3_44100_128"
	private let modelId: String = "eleven_turbo_v2"
	private let similarityBoost: Float = 0.5
	private let stability: Float = 0.5
	private let useSpeakerBoost: Bool = true

	var text: String
	var historyId: String?
	var speech: Data?

	init(_ text: String) {
		self.text = text
	}

	func generateSpeech(_ callback: ((TransportErrorSeverity, String)?) -> Void) {
		let apiKey = PreferenceData.elevenLabsApiKey()
		let voiceId = PreferenceData.elevenLabsVoiceId()
		let dictionaryId = PreferenceData.elevenLabsDictionaryId()
		let dictionaryVersion = PreferenceData.elevenLabsDictionaryVersion()
		let optimizeStreamingLatency = PreferenceData.elevenLabsLatencyReduction()
		guard !apiKey.isEmpty, !voiceId.isEmpty else {
			callback((.settings, "Can't generate speech due to empty api key or voice id"))
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
			   let data = data {
				logger.info("Successful speech generation for \(self.text, privacy: .public)")
				self.speech = data
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
		logger.info("Posting generation request for \(self.text) to ElevenLabs")
		task.resume()
	}

	func downloadSpeech(_ callback: ((TransportErrorSeverity, String)?) -> Void) {

	}
}

final class ElevenLabs: NSObject, AVAudioPlayerDelegate {
	static let shared = ElevenLabs()

	private var pastItems: [String: GeneratedItem] = [:]
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
			guard existing.speech == nil else {
				queueSpeech(existing)
				return
			}
			existing.downloadSpeech() { error in
				guard let error = error else {
					queueSpeech(item)
					return
				}
				// fallback to Apple speech generation
				DispatchQueue.main.async {
					let utterance = AVSpeechUtterance(string: text)
					Self.synthesizer.speak(utterance)
				}
				errorCallback?(error.0, error.1)
			}
		}
		let item = GeneratedItem(text)
		item.generateSpeech() { error in
			guard let error = error else {
				queueSpeech(item)
				return
			}
			// fallback to Apple speech generation
			DispatchQueue.main.async {
				let utterance = AVSpeechUtterance(string: text)
				Self.synthesizer.speak(utterance)
			}
			errorCallback?(error.0, error.1)
		}
	}

	private func queueSpeech(_ item: GeneratedItem) {
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
		guard let speech = pendingItems.first else {
			// no first speech to play, nothing to do
			return
		}
		do {
			speaker = try AVAudioPlayer(data: speech.speech!, fileTypeHint: "mp3")
			if let player = speaker {
				player.delegate = ElevenLabs.shared
				if !player.play() {
					logAnomaly("Couldn't play generated speech")
					logger.error("Couldn't play generated speech")
				}
			}
		}
		catch {
			logger.error("Couldn't create player for speech: \(error, privacy: .public)")
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
