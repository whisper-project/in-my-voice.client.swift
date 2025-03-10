// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import CryptoKit

enum OperatingMode: Int {
    case ask = 0, whisper = 1
}

struct PreferenceData {
    private static var localSettings = UserDefaults.standard
	private static var cloudSettings = NSUbiquitousKeyValueStore.default

    // server endpoint
    #if DEBUG
	static private let altServer = ProcessInfo.processInfo.environment["INMYVOICE_SERVER"] != nil
	static let voiceServer = ProcessInfo.processInfo.environment["INMYVOICE_SERVER"] ?? "https://stage.in-my-voice.whisper-project.org"
	static let profileRoot = altServer ? "dev-" : "stage-"
    #else
    static let voiceServer = "https://in-my-voice.whisper-project.org"
	static let profileRoot = ""
    #endif

    // client ID for this device
    static var clientId: String {
        if let id = localSettings.string(forKey: "client_id") {
            return id
        } else {
            let id = UUID().uuidString
            localSettings.setValue(id, forKey: "client_id")
            return id
        }
    }

	// local profileID
	static var profileId: String {
		get {
			if let id = localSettings.string(forKey: "profile_id") {
				return id
			} else {
				let id = UUID().uuidString
				cloudSettings.setValue(id, forKey: "profile_id")
				return id
			}
		}
		set(id) {
			localSettings.setValue(id, forKey: "profile_id")
		}
	}

	static var isProfileSynced: Bool {
		guard let cloudId = cloudSettings.string(forKey: "profile_id") else {
			return false
		}
		return cloudId == profileId
	}

	static func syncProfileId() {
		cloudSettings.setValue(profileId, forKey: "profile_id")
	}

	// size of text
	static var fontSize: FontSizes.FontSize {
		get {
			max(localSettings.integer(forKey: "font_size_setting"), FontSizes.minTextSize)
		}
		set (new) {
			localSettings.setValue(new, forKey: "font_size_setting")
		}
	}

	// whether to magnify text
	static var useLargeFontSizes: Bool {
		get {
			localSettings.bool(forKey: "use_large_font_sizes_setting")
		}
		set (new) {
			localSettings.setValue(new, forKey: "use_large_font_sizes_setting")
		}
	}

    // alert sounds
    struct AlertSoundChoice: Identifiable {
        var id: String
        var name: String
    }
    static let alertSoundChoices: [AlertSoundChoice] = [
        AlertSoundChoice(id: "air-horn", name: "Air Horn"),
        AlertSoundChoice(id: "bike-horn", name: "Bicycle Horn"),
        AlertSoundChoice(id: "bike-bell", name: "Bicycle Bell"),
    ]
    static var alertSound: String {
        get {
            return localSettings.string(forKey: "alert_sound_setting") ?? "bike-horn"
        }
        set(new) {
            localSettings.setValue(new, forKey: "alert_sound_setting")
        }
    }

	/// whether to show favorites while whispering
	static var showFavorites: Bool {
		get {
			localSettings.bool(forKey: "show_favorites_setting")
		}
		set (new) {
			localSettings.setValue(new, forKey: "show_favorites_setting")
		}
	}

	/// whether to hear typing
	static var hearTyping: Bool {
		get {
			localSettings.bool(forKey: "hear_typing_setting")
		}
		set (new) {
			localSettings.setValue(new, forKey: "hear_typing_setting")
		}
	}

	/// typing sounds
	static let typingSoundChoices = [
		("a", "Old-fashioned Typewriter", "typewriter-two-minutes"),
		("b", "Modern Keyboard", "low-frequency-typing"),
	]
	static let typingSoundDefault = "typewriter-two-minutes"
	static var typingSound: String {
		get {
			let val = localSettings.string(forKey: "typing_sound_choice_setting") ?? typingSoundDefault
			switch val {
			case "low-frequency-typing": return val
			default: return typingSoundDefault
			}
		}
		set(val) {
			for tuple in typingSoundChoices {
				if val == tuple.1 || val == tuple.2 {
					localSettings.set(tuple.2, forKey: "typing_sound_choice_setting")
				}
			}
		}
	}
	static var typingVolume: Double {
		get {
			let diff = localSettings.float(forKey: "typing_volume_setting")
			switch diff {
			case 0.25: return 0.25
			case 0.5: return 0.5
			default: return 1.0
			}
		}
		set(val) {
			var next: Double
			switch val {
			case 0.25: next = val
			case 0.5: next = val
			default: next = 1.0
			}
			localSettings.setValue(next, forKey: "typing_volume_setting")
		}
	}

	/// the current favorites group
	static var currentFavoritesGroup: FavoritesGroup {
		get {
			if let name = localSettings.string(forKey: "current_favorite_tag_setting"),
			   let group = UserProfile.shared.favoritesProfile.getGroup(name) {
				group
			} else {
				UserProfile.shared.favoritesProfile.allGroup
			}
		}
		set(new) {
			localSettings.set(new.name, forKey: "current_favorite_tag_setting")
		}
	}

	/// Preferences
	static private var elevenLabsApiKeyPreference: String {
		get {
			localSettings.string(forKey: "elevenlabs_api_key_preference")?.trimmingCharacters(in: .whitespaces) ?? ""
		}
		set(val) {
			localSettings.setValue(val.trimmingCharacters(in: .whitespaces), forKey: "elevenlabs_api_key_preference")
		}
	}

	static private var elevenLabsVoiceIdPreference: String {
		get {
			localSettings.string(forKey: "elevenlabs_voice_id_preference")?.trimmingCharacters(in: .whitespaces) ?? ""
		}
		set(val) {
			localSettings.setValue(val.trimmingCharacters(in: .whitespaces), forKey: "elevenlabs_voice_id_preference")
		}
	}

	static private var elevenLabsDictionaryIdPreference: String {
		get {
			localSettings.string(forKey: "elevenlabs_dictionary_id_preference")?.trimmingCharacters(in: .whitespaces) ?? ""
		}
		set(val) {
			localSettings.setValue(val.trimmingCharacters(in: .whitespaces), forKey: "elevenlabs_dictionary_id_preference")
		}
	}

	static private var elevenLabsDictionaryVersionPreference: String {
		get {
			localSettings.string(forKey: "elevenlabs_dictionary_version_preference")?.trimmingCharacters(in: .whitespaces) ?? ""
		}
		set(val) {
			localSettings.setValue(val.trimmingCharacters(in: .whitespaces), forKey: "elevenlabs_dictionary_version_preference")
		}
	}

	static private var elevenLabsLatencyReductionPreference: Int {
		get {
			localSettings.integer(forKey: "elevenlabs_latency_reduction_preference") + 1
		}
		set(val) {
			localSettings.setValue(val - 1, forKey: "elevenlabs_latency_reduction_preference")
		}
	}

	static private var interjectionPrefixPreference: String {
		get {
			localSettings.string(forKey: "interjection_prefix_preference")?.trimmingCharacters(in: .whitespaces) ?? ""
		}
		set(val) {
			localSettings.setValue(val.trimmingCharacters(in: .whitespaces), forKey: "interjection_prefix_preference")
		}
	}

	static private var interjectionAlertPreference: String {
		get {
			localSettings.string(forKey: "interjection_alert_preference") ?? ""
		}
		set(val) {
			localSettings.setValue(val, forKey: "interjection_alert_preference")
		}
	}

	static private var historyButtonsPreference: String {
		get {
			localSettings.string(forKey: "history_buttons_preference") ?? "r-i-f"
		}
		set(val) {
			localSettings.setValue(val, forKey: "history_buttons_preference")
		}
	}

	// speech keys
	static func elevenLabsApiKey() -> String {
		return elevenLabsApiKeyPreference
	}
	static func elevenLabsVoiceId() -> String {
		return elevenLabsVoiceIdPreference
	}
	static func elevenLabsDictionaryId() -> String {
		return elevenLabsDictionaryIdPreference
	}
	static func elevenLabsDictionaryVersion() -> String {
		return elevenLabsDictionaryVersionPreference
	}
	static func elevenLabsLatencyReduction() -> Int {
		return elevenLabsLatencyReductionPreference
	}

	// interjection behavior
	static func interjectionPrefix() -> String {
		if interjectionPrefixPreference.isEmpty {
			return ""
		} else {
			return interjectionPrefixPreference + " "
		}
	}

	static func interjectionAlertSound() -> String {
		return interjectionAlertPreference
	}

	static let preferenceVersion = 1

	static func preferencesToJson() -> String {
		let preferences = [
			"version": "\(preferenceVersion)",
			"elevenlabs_api_key_preference": elevenLabsApiKeyPreference,
			"elevenlabs_voice_id_preference": elevenLabsVoiceIdPreference,
			"elevenlabs_dictionary_id_preference": elevenLabsDictionaryIdPreference,
			"elevenlabs_dictionary_version_preference": elevenLabsDictionaryVersionPreference,
			"elevenlabs_latency_reduction_preference": "\(elevenLabsLatencyReductionPreference)",
			"interjection_prefix_preference": interjectionPrefixPreference,
			"interjection_alert_preference": interjectionAlertPreference,
			"history_buttons_preference": historyButtonsPreference,
		]
		guard let json = try? JSONSerialization.data(withJSONObject: preferences, options: .sortedKeys) else {
			fatalError("Can't encode preferences data: \(preferences)")
		}
		return String(decoding: json, as: UTF8.self)
	}

	static func jsonToPreferences(_ json: String) {
		guard let val = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
			  let preferences = val as? [String: String]
		else {
			fatalError("Can't decode preferences data: \(json)")
		}
		let version = Int(preferences["version"] ?? "") ?? 1
		if version != preferenceVersion {
			logAnomaly("Setting preferences from v\(version) preference data, expected v\(preferenceVersion)")
		}
		elevenLabsApiKeyPreference = preferences["elevenlabs_api_key_preference"] ?? ""
		elevenLabsVoiceIdPreference = preferences["elevenlabs_voice_id_preference"] ?? ""
		elevenLabsDictionaryIdPreference = preferences["elevenlabs_dictionary_id_preference"] ?? ""
		elevenLabsDictionaryVersionPreference = preferences["elevenlabs_dictionary_version_preference"] ?? ""
		elevenLabsLatencyReductionPreference = Int(preferences["elevenlabs_latency_reduction_preference"] ?? "") ?? 1
		interjectionPrefixPreference = preferences["interjection_prefix_preference"] ?? ""
		interjectionAlertPreference = preferences["interjection_alert_preference"] ?? ""
		historyButtonsPreference = preferences["history_buttons_preference"] ?? "r-i-f"
	}
}
