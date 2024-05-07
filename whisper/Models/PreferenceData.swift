// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import CoreBluetooth
import CryptoKit

enum OperatingMode: Int {
    case ask = 0, listen = 1, whisper = 2
}

struct PreferenceData {
    private static var defaults = UserDefaults.standard
    
    // publisher URLs
    #if DEBUG
	static let whisperServer = ProcessInfo.processInfo.environment["WHISPER_SERVER"] ?? "https://stage.whisper.clickonetwo.io"
    #else
    static let whisperServer = "https://whisper.clickonetwo.io"
    #endif
    static func publisherUrlToConversationId(url: String) -> (String, String)? {
		let expectedPrefix = whisperServer + "/listen/"
		if url.starts(with: expectedPrefix) {
			let tailEnd = url.index(expectedPrefix.endIndex, offsetBy: 36)
			let tail = url[expectedPrefix.endIndex..<tailEnd]
			if tail.wholeMatch(of: /[-a-zA-Z0-9]{36}/) != nil {
				let rest = url.suffix(from: url.index(tailEnd, offsetBy: 1))
				if rest.isEmpty {
					return (String(tail), String(tail.suffix(12)))
				} else {
					return (String(tail), String(rest))
				}
			}
		}
        return nil
    }
    static func publisherUrl(_ conversation: WhisperConversation) -> String {
		let urlName = conversation.name.compactMap {char in
			if char.isLetter || char.isNumber {
				return String(char)
			} else {
				return "-"
			}
		}.joined()
		return "\(whisperServer)/listen/\(conversation.id)/\(urlName)"
    }
	static let publisherUrlEventMatchString = "\(whisperServer)/listen/*"

    // server (and Ably) client ID for this device
    static var clientId: String {
        if let id = defaults.string(forKey: "whisper_client_id") {
            return id
        } else {
            let id = UUID().uuidString
            defaults.setValue(id, forKey: "whisper_client_id")
            return id
        }
    }
    
    // client secrets for TCP transport
    //
    // Secrets rotate.  The client generates its first secret, and always
    // sets that as both the current and prior secret.  After that, every
    // time the server sends a new secret, the current secret rotates to
    // be the prior secret.  We send the prior secret with every launch,
    // because this allows the server to know when we've gone out of sync
    // (for example, when a client moves from apns dev to apns prod),
    // and it rotates the secret when that happens.  We sign auth requests
    // with the current secret, but the server allows use of the prior
    // secret as a one-time fallback when we've gone out of sync.
    static func lastClientSecret() -> String {
        if let prior = defaults.string(forKey: "whisper_last_client_secret") {
            return prior
        } else {
            let prior = makeSecret()
            defaults.setValue(prior, forKey: "whisper_last_client_secret")
            return prior
        }
    }
    static func clientSecret() -> String {
        if let current = defaults.string(forKey: "whisper_client_secret") {
            return current
        } else {
            let prior = lastClientSecret()
            defaults.setValue(prior, forKey: "whisper_client_secret")
            return prior
        }
    }
    static func updateClientSecret(_ secret: String) {
        // if the new secret is different than the old secret, save the old secret
        if let current = defaults.string(forKey: "whisper_client_secret"), secret != current {
            defaults.setValue(current, forKey: "whisper_last_client_secret")
        }
        defaults.setValue(secret, forKey: "whisper_client_secret")
    }
	static func resetClientSecret() {
		// apparently our secret has gone out of date with the server, so use the
		// one it knows about from us until we receive the new one.
		logger.warning("Resetting client secret to match server expectations")
		defaults.setValue(lastClientSecret(), forKey: "whisper_client_secret")
	}
	static func resetSecretsAndSharingIfServerHasChanged() {
		// if we are operating against a different server than last run, we need
		// to reset our secrets as if this were the very first run.
		// we also have to stop sharing our profile, because the new server doesn't have it
		// NOTE: this needs to be run as early as possible in the launch sequence.
		guard let server = defaults.string(forKey: "whisper_last_used_server") else {
			// we've never launched before, so nothing to do except save the current server
			defaults.set(whisperServer, forKey: "whisper_last_used_server")
			return
		}
		guard server != whisperServer else {
			// still using the same server, nothing to do
			return
		}
		logger.warning("Server change noticed: resetting client secrets and sharing")
		defaults.set(whisperServer, forKey: "whisper_last_used_server")
		defaults.removeObject(forKey: "whisper_last_client_secret")
		defaults.removeObject(forKey: "whisper_client_secret")
		UserProfile.shared.stopSharing()
	}
    static func makeSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else {
            fatalError("Couldn't generate random bytes")
        }
        return Data(bytes).base64EncodedString()
    }

	// content channel ID
	static var contentId: String {
		get {
			if let value = defaults.string(forKey: "content_channel_id") {
				return value
			} else {
				let new = UUID().uuidString
				defaults.setValue(new, forKey: "content_channel_id")
				return new
			}
		}
		set(new) {
			defaults.setValue(new, forKey: "content_channel_id")
		}
	}

	// size of text
	static var sizeWhenWhispering: FontSizes.FontSize {
		get {
			max(defaults.integer(forKey: "size_when_whispering_setting"), FontSizes.minTextSize)
		}
		set (new) {
			defaults.setValue(new, forKey: "size_when_whispering_setting")
		}
	}
	static var sizeWhenListening: FontSizes.FontSize {
		get {
			max(defaults.integer(forKey: "size_when_listening_setting"), FontSizes.minTextSize)
		}
		set (new) {
			defaults.setValue(new, forKey: "size_when_listening_setting")
		}
	}

	// whether to magnify text
	static var magnifyWhenWhispering: Bool {
		get {
			defaults.bool(forKey: "magnify_when_whispering_setting")
		}
		set (new) {
			defaults.setValue(new, forKey: "magnify_when_whispering_setting")
		}
	}
	static var magnifyWhenListening: Bool {
		get { 
			defaults.bool(forKey: "magnify_when_listening_setting")
		}
		set (new) {
			defaults.setValue(new, forKey: "magnify_when_listening_setting")
		}
	}

    // whether to speak past text
    static var speakWhenWhispering: Bool {
        get {
			defaults.bool(forKey: "speak_when_whispering_setting")
		}
        set (new) {
			defaults.setValue(new, forKey: "speak_when_whispering_setting")
		}
    }
    static var speakWhenListening: Bool {
        get {
			defaults.bool(forKey: "speak_when_listening_setting")
		}
        set (new) {
			defaults.setValue(new, forKey: "speak_when_listening_setting")
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
            return defaults.string(forKey: "alert_sound_setting") ?? "bike-horn"
        }
        set(new) {
            defaults.setValue(new, forKey: "alert_sound_setting")
        }
    }
    
	/// Preferences
	static private var whisperTapPreference: String {
		get {
			defaults.string(forKey: "whisper_tap_preference") ?? "show"
		}
		set(val) {
			defaults.setValue(val, forKey: "whisper_tap_preference")
		}
	}

	static private var listenTapPreference: String {
		get {
			defaults.string(forKey: "listen_tap_preference") ?? "show"
		}
		set(val) {
			defaults.setValue(val, forKey: "listen_tap_preference")
		}
	}

	static private var newestWhisperLocationPreference: String {
		get {
			defaults.string(forKey: "newest_whisper_location_preference") ?? "bottom"
		}
		set(val) {
			defaults.setValue(val, forKey: "newest_whisper_location_preference")
		}
	}

	static private var elevenLabsApiKeyPreference: String {
		get {
			defaults.string(forKey: "elevenlabs_api_key_preference") ?? ""
		}
		set(val) {
			defaults.setValue(val, forKey: "elevenlabs_api_key_preference")
		}
	}

	static private var elevenLabsVoiceIdPreference: String {
		get {
			defaults.string(forKey: "elevenlabs_voice_id_preference") ?? ""
		}
		set(val) {
			defaults.setValue(val, forKey: "elevenlabs_voice_id_preference")
		}
	}

	static private var elevenLabsLatencyReductionPreference: String {
		get {
			"\(defaults.integer(forKey: "elevenlabs_latency_reduction_preference") + 1)"
		}
		set(val) {
			defaults.setValue((Int(val) ?? 1) - 1, forKey: "elevenlabs_latency_reduction_preference")
		}
	}

	// behavior for Whisper tap
	static func whisperTapAction() -> String {
		return whisperTapPreference
	}

	// behavior for Listen tap
	static func listenTapAction() -> String {
		return defaults.string(forKey: "listen_tap_preference") ?? "show"
	}

	// layout control of listeners
	static func listenerMatchesWhisperer() -> Bool {
		return newestWhisperLocationPreference == "bottom"
	}

	// speech keys
	static func elevenLabsApiKey() -> String {
		return elevenLabsApiKeyPreference
	}
	static func elevenLabsVoiceId() -> String {
		return elevenLabsVoiceIdPreference
	}
	static func elevenLabsLatencyReduction() -> Int {
		return Int(elevenLabsLatencyReductionPreference) ?? 1
	}

	// server-side logging
	static var doPresenceLogging: Bool {
		get {
			return !defaults.bool(forKey: "do_not_log_to_server_setting")
		}
		set (val) {
			defaults.setValue(val, forKey: "do_not_log_to_server_setting")
		}
	}

	static func preferencesToJson() -> String {
		let preferences = [
			"whisper_tap_preference": whisperTapPreference,
			"listen_tap_preference": listenTapPreference,
			"newest_whisper_location_preference": newestWhisperLocationPreference,
			"elevenlabs_api_key_preference": elevenLabsApiKeyPreference,
			"elevenlabs_voice_id_preference": elevenLabsVoiceIdPreference,
			"elevenlabs_latency_reduction_preference": elevenLabsLatencyReductionPreference,
		]
		guard let json = try? JSONSerialization.data(withJSONObject: preferences, options: .sortedKeys) else {
			fatalError("Can't encode preferences data: \(preferences)")
		}
		return String(decoding: json, as: UTF8.self)
	}

	static func jsonToPreferences(_ json: String) {
		guard let val = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
			  let preferences = val as? [String:String]
		else {
			fatalError("Can't decode preferences data: \(json)")
		}
		whisperTapPreference = preferences["whisper_tap_preference"] ?? "show"
		listenTapPreference = preferences["listen_tap_preference"] ?? "show"
		newestWhisperLocationPreference = preferences["newest_whisper_location_preference"] ?? "bottom"
		elevenLabsApiKeyPreference = preferences["elevenlabs_api_key_preference"] ?? ""
		elevenLabsVoiceIdPreference = preferences["elevenlabs_voice_id_preference"] ?? ""
		elevenLabsLatencyReductionPreference = preferences["elevenlabs_latency_reduction_preference"] ?? "1"
	}
}
