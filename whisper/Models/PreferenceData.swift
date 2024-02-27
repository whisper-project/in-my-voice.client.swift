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
	static var whisperServer = ProcessInfo.processInfo.environment["WHISPER_SERVER"] ?? "https://stage.whisper.clickonetwo.io"
    #else
    static var whisperServer = "https://whisper.clickonetwo.io"
    #endif
    static func publisherUrlToConversationId(url: String) -> String? {
		let expectedPrefix = whisperServer + "/listen/"
		if url.starts(with: expectedPrefix) {
			let tail = url.suffix(36)
			if tail.wholeMatch(of: /[-a-zA-Z0-9]{36}/) != nil {
				return String(tail)
			}
		}
        return nil
    }
    static func publisherUrl(_ conversationId: String) -> String {
        return "\(whisperServer)/listen/\(conversationId)"
    }
    
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
    static func clientSecret() -> String? {
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
	static func resetSecretsIfServerHasChanged() {
		// if we are operating against a different server than last run, we need
		// to reset our secrets as if this were the very first run.
		// NOTE: this needs to be run as early as possible in the launch sequence.
		if let server = defaults.string(forKey: "whisper_last_used_server"), server == whisperServer {
			// still using the same server, nothing to do
			return
		}
		logger.warning("Server change noticed: resetting client secrets")
		defaults.set(whisperServer, forKey: "whisper_last_used_server")
		defaults.removeObject(forKey: "whisper_last_client_secret")
		defaults.removeObject(forKey: "whisper_client_secret")
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

    // layout control of listeners
    static func listenerMatchesWhisperer() -> Bool {
        return defaults.string(forKey: "newest_whisper_location_preference") == "bottom"
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

    // require Bluetooth listeners to pair?
    static func requireAuthentication() -> Bool {
        let result = defaults.bool(forKey: "listener_authentication_preference")
        return result
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
            return defaults.string(forKey: "alert_sound_preference") ?? "bike-horn"
        }
        set(new) {
            defaults.setValue(new, forKey: "alert_sound_preference")
        }
    }
    
    // metrics of errors to send in diagnostics to server
    static var droppedErrorCount: Int {
        get {
            defaults.integer(forKey: "dropped_error_count")
        }
        set(newVal) {
            defaults.setValue(newVal, forKey: "dropped_error_count")
        }
    }
	static var bluetoothErrorCount: Int {
		get {
			defaults.integer(forKey: "bluetooth_error_count")
		}
		set(newVal) {
			defaults.setValue(newVal, forKey: "bluetooth_error_count")
		}
	}
	static var tcpErrorCount: Int {
		get {
			defaults.integer(forKey: "tcp_error_count")
		}
		set(newVal) {
			defaults.setValue(newVal, forKey: "tcp_error_count")
		}
	}
    static var authenticationErrorCount: Int {
        get {
            defaults.integer(forKey: "authentication_error_count")
        }
        set(newVal) {
            defaults.setValue(newVal, forKey: "authentication_error_count")
        }
    }

	// speech keys
	static func elevenLabsApiKey() -> String {
		return defaults.string(forKey: "elevenlabs_api_key_preference") ?? ""
	}
	static func elevenLabsVoiceId() -> String {
		return defaults.string(forKey: "elevenlabs_voice_id_preference") ?? ""
	}
	static func elevenLabsLatencyReduction() -> Int {
		return defaults.integer(forKey: "elevenlabs_latency_reduction_preference") + 1
	}
}
