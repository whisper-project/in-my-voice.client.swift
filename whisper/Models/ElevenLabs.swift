// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import AVFAudio

final class ElevenLabs: NSObject, AVAudioPlayerDelegate {
	static let shared = ElevenLabs()

	private let apiRoot: String = "https://api.elevenlabs.io/v1"
	private var outputFormat: String = "mp3_44100_128"
	private var modelId: String = "eleven_turbo_v2"
	private var similarityBoost: Float = 0.5
	private var stability: Float = 0.5
	private var useSpeakerBoost: Bool = true
	private var speeches: [Data] = []
	private var speaker: AVAudioPlayer?
	private var emptyTextCount: Int = 0

	func speakText(text: String) {
		guard !text.isEmpty else {
			emptyTextCount += 1
			if emptyTextCount == 2 {
				abortCurrentSpeech()
				emptyTextCount = 0
			}
			return
		}
		emptyTextCount = 0
		let apiKey = PreferenceData.elevenLabsApiKey()
		let voiceId = PreferenceData.elevenLabsVoiceId()
		let optimizeStreamingLatency = PreferenceData.elevenLabsLatencyReduction()
		guard !apiKey.isEmpty, !voiceId.isEmpty else {
			logger.error("Can't generate speech due to empty api key or voice id")
			return
		}
		let endpoint = "\(apiRoot)/text-to-speech/\(voiceId)/stream"
		let query = "?output_format=\(outputFormat)&optimize_streaming_latency=\(optimizeStreamingLatency)"
		let body: [String: Any] = [
			"model_id": modelId,
			"text": text,
			"voice_settings": [
				"similarity_boost": similarityBoost,
				"stability": stability,
				"use_speaker_boost": useSpeakerBoost
			]
		]
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
				logger.error("Failed to generate speech: \(String(describing: error))")
				return
			}
			guard let response = response as? HTTPURLResponse else {
				logger.error("Received non-HTTP response on speech generation: \(String(describing: response), privacy: .public)")
				return
			}
			if response.statusCode == 200,
			   let data = data {
				logger.info("Successful speech generation")
				self.queueSpeech(data)
				return
			}
			logger.error("Speech generation of \(text, privacy: .public) got status \(response.statusCode, privacy: .public)")
			guard let data = data,
				  let body = try? JSONSerialization.jsonObject(with: data),
				  let obj = body as? [String:Any] else {
				logger.error("Can't deserialize speech generation response body: \(String(describing: data), privacy: .public)")
				return
			}
			logger.error("Error details of speech generation: \(obj, privacy: .public)")
		}
		logger.info("Posting generation request to ElevenLabs")
		task.resume()
	}

	private func queueSpeech(_ data: Data) {
		DispatchQueue.main.async {
			self.speeches.append(data)
			if self.speeches.count == 1 {
				// this speech is not queued behind another
				self.playFirstSpeech()
			}
		}
	}

	@MainActor
	private func playFirstSpeech() {
		guard let speech = speeches.first else {
			// no first speech to play, nothing to do
			return
		}
		do {
			speaker = try AVAudioPlayer(data: speech, fileTypeHint: "mp3")
			if let player = speaker {
				player.delegate = ElevenLabs.shared
				if !player.play() {
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
		if !speeches.isEmpty {
			// dequeue the last speech
			speeches.removeFirst()
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
