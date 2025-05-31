// Copyright 2025 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI
import AVFAudio

struct AppleSettingsView: View {
	@AppStorage("preferred_voice_identifier") var selectedAppleVoiceId: String?

	@State private var isChoosingVoice: Bool = false
	@State private var voices: [AVSpeechSynthesisVoice] = []
	@State private var filteredVoices: [AVSpeechSynthesisVoice] = []
	@State private var selectedVoiceId: String?
	@State private var restrictLocale: Bool = true
	@State private var selectedGender: AVSpeechSynthesisVoiceGender?
	@State private var elevenLabsEnabled: Bool = ElevenLabs.isEnabled()

	@StateObject private var elevenLabs = ElevenLabs.shared

	var body: some View {
		if !isChoosingVoice {
			if elevenLabsEnabled {
				Text("You have chosen to use an ElevenLabs voice. Apple's built-in speech-to-text will be used when you are offline.")
					.onChange(of: elevenLabs.timestamp) {
						elevenLabsEnabled = ElevenLabs.isEnabled()
					}
			} else {
				Text("You are using Apple's built-in speech-to-text capabilities.").lineLimit(nil)
					.onChange(of: elevenLabs.timestamp) {
						elevenLabsEnabled = ElevenLabs.isEnabled()
					}
			}
			if let voice = loadVoice(selectedAppleVoiceId) {
				Text("You have selected \(voice.name) as your preferred Apple voice.")
				HStack {
					Button("Play a sample") {
						ElevenLabs.shared.playAppleVoice(voice: voice, text: "This is a sample of what \(voice.name) sounds like.")
					}
					Spacer()
					Button("Change voice") {
						isChoosingVoice = true
					}
					Spacer()
					Button("Use system default") {
						PreferenceData.preferredVoiceIdentifier = nil
					}
				}
				.buttonStyle(BorderlessButtonStyle())
			} else {
				Text("You are using the default system voice.")
				HStack {
					Button("Play a sample") {
						ElevenLabs.shared.playAppleVoice(voice: nil, text: "This is a sample of the system voice.")
					}
					Spacer()
					Button("Choose a voice") {
						isChoosingVoice = true
					}
				}
				.buttonStyle(BorderlessButtonStyle())
			}
		} else {
			Text("Your device has access to \(voices.count) voices.")
				.onAppear(perform: filterVoices)
			Text("You can use filters to narrow down the list:")
			Toggle("Restrict to my language", isOn: $restrictLocale)
				.onChange(of: restrictLocale) {
					filterVoices()
				}
			Picker("Gender", selection: $selectedGender) {
				Text("(Any Gender)").tag(nil as AVSpeechSynthesisVoiceGender?)
				Text("Unspecified").tag(AVSpeechSynthesisVoiceGender.unspecified)
				Text("Female").tag(AVSpeechSynthesisVoiceGender.female)
				Text("Male").tag(AVSpeechSynthesisVoiceGender.male)
			}
			.onChange(of: selectedGender) {
				filterVoices()
			}
			Text("There are \(filteredVoices.count) voices that match your filters.")
			Text("Try them out and confirm your choice when ready.")
			Picker("Voice", selection: $selectedVoiceId) {
				Text("(no selection)").tag(nil as String?)
				ForEach(filteredVoices, id: \.identifier) { voice in
					Text(voice.name).tag(voice.identifier)
				}
			}
			HStack {
				Button("Preview voice") {
					if let voice = loadVoice(selectedVoiceId) {
						ElevenLabs.shared.playAppleVoice(voice: voice, text: "This is a sample of what \(voice.name) sounds like.")
					} else {
						ElevenLabs.shared.playAppleVoice(voice: nil, text: "Sorry, There's a problem with that voice. Try another one.")
					}
				}
				.disabled(selectedVoiceId == nil)
				Spacer()
				Button("Set as my voice") {
					if loadVoice(selectedVoiceId) != nil {
						PreferenceData.preferredVoiceIdentifier = selectedVoiceId
						ElevenLabs.shared.loadFallbackVoice()
						isChoosingVoice = false
					} else {
						ElevenLabs.shared.playAppleVoice(voice: nil, text: "Sorry, There is a problem with that voice. Try another one.")
					}
				}
				.disabled(selectedVoiceId == nil)
				Spacer()
				Button("Cancel") {
					isChoosingVoice = false
				}
			}
			.buttonStyle(BorderlessButtonStyle())
		}
	}

    private func loadVoice(_ voiceId: String?) -> AVSpeechSynthesisVoice? {
		guard let ident = voiceId,
			  let voice = AVSpeechSynthesisVoice(identifier: ident) else
		{
		   return nil
		}
		return voice
	}

	private func filterVoices() {
		voices = AVSpeechSynthesisVoice.speechVoices()
		let currentLocale = AVSpeechSynthesisVoice.currentLanguageCode()
		filteredVoices = []
		for voice in voices {
			if restrictLocale && voice.language != currentLocale {
				continue
			}
			if selectedGender != nil && voice.gender != selectedGender {
				continue
			}
			filteredVoices.append(voice)
		}
		filteredVoices.sort { $0.name < $1.name }
		selectedVoiceId = filteredVoices.first?.identifier
	}
}

#Preview {
    AppleSettingsView()
}
