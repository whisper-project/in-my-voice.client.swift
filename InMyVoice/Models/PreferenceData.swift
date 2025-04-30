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
	static private let stageServer = "https://stage.in-my-voice.whisper-project.org"
	static private let prodServer = "https://in-my-voice.whisper-project.org"
    #if DEBUG
	static private let altServer = ProcessInfo.processInfo.environment["INMYVOICE_SERVER"]
	static let appServer = altServer ?? stageServer
	static let profileRoot = altServer != nil ? "dev-" : "stage-"
    #else
    static let appServer = prodServer
	static let profileRoot = ""
    #endif

	// website endpoints
	static var website = "https://whisper-project.github.io/in-my-voice.client.swift"
	static func aboutSite() -> URL {
		return URL(string: website)!
	}
	static func supportSite() -> URL {
		return URL(string: "\(website)/support.html")!
	}
	static func instructionSite() -> URL {
		return URL(string: "\(website)/instructions.html")!
	}

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

	// whether this user is in the study, this is sent by the server
	// whenever it changes, but it is cached in case we're offline.
	//
	// It defaults to false for new installations.
	static private var _inStudy: Bool?
	static var inStudy: Bool {
		get {
			return _inStudy ?? {
				_inStudy = localSettings.bool(forKey: "in_study")
				return _inStudy!
			}()
		}
		set(val) {
			_inStudy = val
			localSettings.setValue(val, forKey: "in_study")
		}
	}

	// whether to collect stats for users not in the study, this is sent by the server
	// whenever it changes, but it is cached between launches in case we're offline.
	//
	// It defaults to true for new installations.
	static private var _collectNonStudyStats: Bool?
	static var collectNonStudyStats: Bool {
		get {
			return _collectNonStudyStats ?? {
				_collectNonStudyStats = !localSettings.bool(forKey: "only_collect_study_stats")
				return _collectNonStudyStats!
			}()
		}
		set(val) {
			_collectNonStudyStats = val
			localSettings.setValue(!val, forKey: "only_collect_study_stats")
		}
	}

	// local profileID
	static var profileId: String? {
		get {
			localSettings.string(forKey: "profile_id")
		}
		set(id) {
			if let id = id {
				localSettings.setValue(id, forKey: "profile_id")
			} else {
				localSettings.removeObject(forKey: "profile_id")
			}
		}
	}

	static var cloudProfileId: String? {
		get {
			return cloudSettings.string(forKey: "profile_id")
		}
		set (id) {
			if let id = id {
				cloudSettings.set(id, forKey: "profile_id")
			} else {
				cloudSettings.removeObject(forKey: "profile_id")
			}
		}
	}

	static func syncProfile() {
		cloudSettings.synchronize()
		let id = profileId ?? ""
		let cloudId = cloudProfileId ?? ""
		if id == "" {
			if cloudId != "" {
				logger.info("Using profile ID from cloud: \(cloudId, privacy: .public)")
				profileId = cloudId
			} else {
				let id = UUID().uuidString
				logger.info("No local or cloud Profile ID found, setting both to: \(id, privacy: .public)")
				profileId = id
				cloudProfileId = id
			}
		} else if cloudId == "" {
			logger.info( "No cloud profile ID found, saving local to cloud: \(id, privacy: .public)")
			cloudProfileId = id
		} else if id == cloudId {
			logger.info("Local and cloud Profile IDs match: \(id, privacy: .public)")
		} else {
			ServerProtocol.notifyAnomaly("Local profile ID (\(id)) doesn't match cloud profile ID (\(cloudId))")
			if UUID(uuidString: cloudId) == nil {
				let id = UUID().uuidString
				ServerProtocol.notifyAnomaly("Cloud profile ID is not a valid UUID, resetting local and cloud to \(id)")
				profileId = id
				cloudProfileId = id
			} else {
				ServerProtocol.notifyAnomaly("Resetting local profile ID to \(cloudId)")
				profileId = cloudId
			}
		}
	}

	// preferred Apple voice
	static var preferredVoiceIdentifier: String? {
		get {
			localSettings.string(forKey: "preferred_voice_identifier")
		}
		set(id) {
			if let id = id {
				localSettings.setValue(id, forKey: "preferred_voice_identifier")
			} else {
				localSettings.removeObject(forKey: "preferred_voice_identifier")
			}
		}
	}

	// last-known 3rd-party speech service usage percentage
	static var lastUsagePercentage: Int? {
		get {
			localSettings.object(forKey: "last_usage_percentage_setting") as? Int
		}
		set (new) {
			localSettings.set(new, forKey: "last_usage_percentage_setting")
		}
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
			if (platformInfo == "mac") {
				return false
			} else {
				return localSettings.bool(forKey: "use_large_font_sizes_setting")
			}
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
			   let group = FavoritesProfile.shared.getGroup(name) {
				group
			} else {
				FavoritesProfile.shared.allGroup
			}
		}
		set(new) {
			localSettings.set(new.name, forKey: "current_favorite_tag_setting")
		}
	}

	/// Root.plist settings
	static private var interjectionPrefixSetting: String {
		get {
			localSettings.string(forKey: "interjection_prefix_setting")?.trimmingCharacters(in: .whitespaces) ?? ""
		}
		set(val) {
			localSettings.setValue(val.trimmingCharacters(in: .whitespaces), forKey: "interjection_prefix_setting")
		}
	}

	static private var interjectionAlertSetting: String {
		get {
			localSettings.string(forKey: "interjection_alert_setting") ?? ""
		}
		set(val) {
			localSettings.setValue(val, forKey: "interjection_alert_setting")
		}
	}

	static private var historyButtonsSetting: String {
		get {
			localSettings.string(forKey: "history_buttons_setting") ?? "r-i-f"
		}
		set(val) {
			localSettings.setValue(val, forKey: "history_buttons_setting")
		}
	}

	// interjection behavior
	static func interjectionPrefix() -> String {
		if interjectionPrefixSetting.isEmpty {
			return ""
		} else {
			return interjectionPrefixSetting + " "
		}
	}

	static func interjectionAlertSound() -> String {
		return interjectionAlertSetting
	}
}
