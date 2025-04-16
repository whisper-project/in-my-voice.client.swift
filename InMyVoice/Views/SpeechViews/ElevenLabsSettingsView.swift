// Copyright 2025 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

let intro = """
Every ElevenLabs account has the ability to generate an [API key](https://elevenlabs.io/app/settings/api-keys), \
which is long string of letters and numbers that starts with "sk_". Once you generate \
your API key, enter it here and validate it so this app can use it to read your text.
"""

struct ElevenLabsSettingsView: View {
	enum ValidationState {
		case idle
		case validating
	}

	@State private var timestamp = ElevenLabs.shared.timestamp
	@State private var isEnabled: Bool = ElevenLabs.isEnabled()
	@State private var apiKey: String = ElevenLabs.apiKey
	@State private var voiceId: String? = ElevenLabs.voiceId
	@State private var voices: [VoiceInfo] = ElevenLabs.voices
	@State private var filteredVoices: [VoiceInfo] = []
	@State private var hideStockVoices: Bool = false
	@State private var labelOptions: [LabelOption] = []
	@State private var voiceName: String = ElevenLabs.voiceName
	@State private var apiKeyValidated: Bool = ElevenLabs.isEnabled()
	@State private var voiceIdValidated: Bool = ElevenLabs.isEnabled()
	@State private var validationState: ValidationState = .idle
	@State private var validationSucceeded: Bool?
	@State private var previewUrl: URL?

	@StateObject private var elevenLabs = ElevenLabs.shared

    var body: some View {
		if isEnabled && apiKeyValidated && voiceIdValidated {
			Text("Your ElevenLabs account is enabled and you have chosen a voice. You can make changes here.")
			HStack(spacing: 5) {
				Text("Your ElevenLabs voice is named:")
				Text(voiceName)
			}
			ElevenLabsUsageView()
			HStack {
				Button("Change API Key") {
					apiKeyValidated = false
					voiceIdValidated = false
					voiceId = nil
					validationSucceeded = nil
				}
				Spacer()
				Button("Change Voice") {
					voiceIdValidated = false
					voiceId = nil
					validationSucceeded = nil
					validateApiKey()
				}
				Spacer()
				Button("Disable ElevenLabs") {
					eraseApiKey()
				}
			}
			.buttonStyle(BorderlessButtonStyle())
			.onChange(of: elevenLabs.timestamp) { updateFromElevenLabs() }
		} else if !apiKeyValidated {
			// we are editing the API key, no voice yet
			switch validationState {
			case .idle:
				if validationSucceeded ?? true {
					Text(LocalizedStringKey(intro))
						.lineLimit(nil)
				} else {
					Text("Sorry, the API key you entered is invalid. Please try again.")
						.lineLimit(nil)
				}
				TextField("ElevenLabs API Key", text: $apiKey, axis: .vertical)
				HStack {
					Button("Validate API Key") {
						validateApiKey()
					}
					.disabled(apiKey.isEmpty || !apiKey.hasPrefix("sk_"))
					Spacer()
					Button("Cancel") {
						updateFromElevenLabs(true)
					}
					.disabled(!isEnabled)
				}
				.buttonStyle(BorderlessButtonStyle())
				.onChange(of: elevenLabs.timestamp) { updateFromElevenLabs() }
			case .validating:
				ProgressView()
			}
		} else {
			// we are editing the voice selection
			switch validationState {
			case .idle:
				Text("Your API key has access to \(voices.count) voices.")
				Text("You can use these filters to narrow down the list:")
				Toggle("Hide stock voices", isOn: $hideStockVoices)
					.onChange(of: hideStockVoices) {
						filterVoices()
					}
				ForEach(labelOptions) { option in
					LabelOptionPicker(option: option, doFilter: filterVoices)
				}
				Text("There are \(filteredVoices.count) voices that match your filters.")
				Text("Try them out and confirm your choice when ready.")
				Picker("Voice", selection: $voiceId) {
					Text("(no selection)").tag(nil as String?)
					ForEach(filteredVoices, id: \.voiceId) { voice in
						Text(voice.name).tag(voice.voiceId)
					}
				}
				HStack {
					Button("Preview voice") {
						if let previewUrl = previewUrl {
							ElevenLabs.shared.playAudioUrl(previewUrl)
						}
					}
					.disabled(previewUrl == nil)
					Spacer()
					Button("Set as my voice") {
						validateVoiceId()
					}
					.disabled(voiceId == nil)
				}
				.buttonStyle(BorderlessButtonStyle())
				.onChange(of: voiceId) {
					if let voiceId = voiceId,
					   let voice = voices.first(where: { $0.voiceId == voiceId })
					{
						previewUrl = URL(string: voice.previewUrl)
					}
				}
				.onChange(of: elevenLabs.timestamp) { updateFromElevenLabs() }
			case .validating:
				ProgressView("Fetching voice data...")
			}
		}
    }

	private func updateFromElevenLabs(_ force: Bool = false) {
		guard force || timestamp != elevenLabs.timestamp else { return }
		timestamp = elevenLabs.timestamp
		if ElevenLabs.isEnabled() {
			isEnabled = true
			apiKey = ElevenLabs.apiKey
			apiKeyValidated = true
			voiceId = ElevenLabs.voiceId
			voiceIdValidated = true
			voiceName = ElevenLabs.voiceName
			voices = ElevenLabs.voices
		} else {
			isEnabled = false
			apiKey = ""
			apiKeyValidated = false
			voiceId = nil
			voiceIdValidated = false
			voiceName = ""
			voices = []
		}
	}

	private func validateApiKey() {
		validationState = .validating
		ElevenLabs.shared.proposeSettings(apiKey: apiKey) { ok in
			validationState = .idle
			apiKeyValidated = ok
			if ok {
				prepareVoiceChoices()
			}
		}
	}

	private func eraseApiKey() {
		validationState = .validating
		ElevenLabs.shared.proposeSettings(apiKey: "") { ok in
			validationState = .idle
			if ok {
				apiKey = ""
				voiceId = nil
				apiKeyValidated = false
				voiceIdValidated = false
				voiceName = ""
				voices = []
			}
		}
	}

	private func validateVoiceId() {
		if let voiceId = voiceId {
			validationState = .validating
			ElevenLabs.shared.proposeSettings(apiKey: apiKey, voiceId: voiceId) { ok in
				self.validationState = .idle
				if ok {
					// force the update if the settings are the same as before,
					// otherwise the timestamp update will make it happen
					updateFromElevenLabs(apiKey == ElevenLabs.apiKey && voiceId == ElevenLabs.voiceId)
				} else {
					ServerProtocol.notifyAnomaly("Voice ID validation failed but voice was received from server")
				}
			}
		}
	}

	private class LabelOption: Identifiable {
		let id: String
		let label: String
		var values: [String]
		var value: String?

		static let idLabelMap: [String: String] = [
			"category": "Category",
			"description": "Description",
			"gender": "Gender",
			"age": "Age",
			"accent": "Accent",
			"use_case": "Use Case",
		]

		init(_ id: String) {
			self.id = id
			self.label = Self.idLabelMap[id] ?? id
			self.values = []
			self.value = nil
		}
	}

	private struct LabelOptionPicker: View {
		var option: LabelOption
		var doFilter: () -> Void

		@State var selectedValue: String?

		var body: some View {
			Picker("\(option.label)", selection: $selectedValue) {
				Text("(Any Value)").tag(nil as String?)
				ForEach(option.values, id: \.self) { value in
					Text(value).tag(value)
				}
			}
			.onChange(of: selectedValue) {
				option.value = selectedValue
				doFilter()
			}
		}
	}

	private func prepareVoiceChoices() {
		voices = ElevenLabs.voices
		let categoryOption = LabelOption("category")
		labelOptions = [categoryOption]
		for voice in voices {
			if !categoryOption.values.contains(where: { $0 == voice.category }) {
				categoryOption.values.append(voice.category)
			}
			for var (label, value) in voice.labels {
				label = label.lowercased().trimmingCharacters(in: .whitespaces)
				value = value.trimmingCharacters(in: .whitespaces)
				var option = labelOptions.first(where: { $0.id == label })
				if option == nil {
					option = LabelOption(label)
					labelOptions.append(option!)
				}
				if !option!.values.contains(where: { $0 == value }) {
					option!.values.append(value)
				}
			}
		}
		labelOptions.sort { $0.label < $1.label }
		filterVoices()
	}

	private func filterVoices() {
		filteredVoices = []
		voiceLoop: for voice in voices {
			if !voice.isOwner && hideStockVoices {
				continue
			}
			for option in labelOptions {
				if let wanted = option.value, wanted != voice.labels[option.id] {
					continue voiceLoop
				}
			}
			filteredVoices.append(voice)
		}
		filteredVoices.sort { $0.name < $1.name }
		voiceId = filteredVoices.first?.voiceId
	}
}

#Preview {
    ElevenLabsSettingsView()
}
