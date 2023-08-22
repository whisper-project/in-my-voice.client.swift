// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import CoreBluetooth

enum OperatingMode: Int {
    case ask = 0, listen = 1, whisper = 2
}

struct PreferenceData {
    private static var defaults = UserDefaults.standard
    static var clientId: String = {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "whisper_client_id") {
            return id
        } else {
            let id = UUID().uuidString
            defaults.setValue(id, forKey: "whisper_client_id")
            return id
        }
    }()
    static func clientSecret() -> String? {
        return defaults.string(forKey: "whisper_client_secret")
    }
    static func updateClientSecret(_ secret: String) {
        defaults.setValue(secret, forKey: "whisper_client_secret")
    }
    static func initialMode() -> OperatingMode {
        let val = defaults.integer(forKey: "initial_mode_preference")
        return OperatingMode(rawValue: val) ?? .ask
    }
    static func startSpeaking() -> Bool {
        return defaults.bool(forKey: "read_aloud_preference")
    }
    static func userName() -> String {
        let name = defaults.string(forKey: "device_name_preference") ?? ""
        return name
    }
    static func updateUserName(_ name: String) {
        defaults.setValue(name, forKey: "device_name_preference")
    }
    static func requireAuthentication() -> Bool {
        let result = defaults.bool(forKey: "listener_authentication_preference")
        return result
    }
    static func alertSound() -> String {
        return defaults.string(forKey: "alert_sound_preference") ?? "bike-horn"
    }
}
