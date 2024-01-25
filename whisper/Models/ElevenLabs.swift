// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import AVFAudio

final class ElevenLabs {
	static let shared = ElevenLabs()

	private let apiRoot: String = "https://api.elevenlabs.io/v1"
	private var outputFormat: String = "mp3_44100_32"
	private var optimizeStreamingLatency: Int = 0
	private var modelId: String = "eleven_turbo_v2"
	private var similarityBoost: Float = 0.8
	private var stability: Float = 0.3
	private var useSpeakerBoost: Bool = true
	private var speaker: AVAudioPlayer?

	func speakText(text: String) {
		let apiKey = PreferenceData.elevenLabsApiKey()
		let voiceId = PreferenceData.elevenLabsVoiceId()
		guard !apiKey.isEmpty, !voiceId.isEmpty else {
			logger.error("Can't generate speech due to empty api key or voice id")
			return
		}
		let endpoint = "\(apiRoot)/text-to-speech/\(voiceId)"
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
				logger.error("Received non-HTTP response on speech generation: \(String(describing: response))")
				return
			}
			if response.statusCode == 200,
			   let data = data {
				logger.info("Successful text generation")
				self.playSpeech(data)
				return
			}
			logger.error("Received unexpected response speech generation: \(response.statusCode)")
			guard let data = data,
				  let body = try? JSONSerialization.jsonObject(with: data),
				  let obj = body as? [String:Any] else {
				logger.error("Can't deserialize speech generation response body: \(String(describing: data))")
				return
			}
			logger.error("Error details of speech generation: \(obj)")
		}
		logger.info("Posting generation request to ElevenLabs")
		task.resume()
	}

	private func playSpeech(_ data: Data) {
		DispatchQueue.main.async {
			self.speaker = try? AVAudioPlayer(data: data, fileTypeHint: "mp3")
			if let player = self.speaker {
				if !player.play() {
					logger.error("Couldn't play generated speech")
				}
			} else {
				logger.error("Couldn't create player for generated speech")
			}
		}
	}
}
