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
    #if DEBUG
    static var whisperServer = "https://stage.whisper.clickonetwo.io"
    #else
    static var whisperServer = "https://whisper.clickonetwo.io"
    #endif
    static func publisherUrlToClientId(url: String) -> String? {
        let publisherRegex = /https:\/\/(stage\.)?whisper.clickonetwo.io\/subscribe\/([-a-zA-Z0-9]{36})/
        guard let match = url.wholeMatch(of: publisherRegex) else {
            return nil
        }
        return String(match.2)
    }
    static var clientId: String = {
        if let id = defaults.string(forKey: "whisper_client_id") {
            return id
        } else {
            let id = UUID().uuidString
            defaults.setValue(id, forKey: "whisper_client_id")
            return id
        }
    }()
    // Secrets rotate.  The client generates its first secret, and always
    // sets that as both the current and prior secret.  After that, every
    // time the server sends a new secret, the current secret rotates to
    // be the prior secret.  We send the prior secret with every launch,
    // because this allows the server to know when we've gone out of sync
    // (for example, when a client moves from apns dev to apns prod),
    // and it rotates the secret when that happens.  We sign auth requests
    // with the current secret, but the server allows use of the prior
    // secret as a one-time fallback when we've gone out of sync.
    static func lastClientSecret() -> String? {
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
    static func makeSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else {
            fatalError("Couldn't generate random bytes")
        }
        return Data(bytes).base64EncodedString()
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
    static func paidReceiptId() -> String? {
        #if DEBUG
        return defaults.string(forKey: "paid_receipt_id") ?? "debug_build_is_paid"
        #else
        return defaults.string(forKey: "paid_receipt_id") ?? "testing_build_is_paid"
        #endif
    }
    static func updatePaidReceiptId(receiptId: String?) {
        if let receiptId = receiptId {
            defaults.setValue(receiptId, forKey: "paid_receipt_id")
        } else {
            defaults.removeObject(forKey: "paid_receipt_id")
        }
    }
    static var lastSubscriberUrl: String? {
        get {
            defaults.string(forKey: "last_subscriber_url")
        }
        set(newUrl) {
            if newUrl != nil {
                defaults.setValue(newUrl, forKey: "last_subscriber_url")
            } else {
                defaults.removeObject(forKey: "last_subscriber_url")
            }
        }
    }
}
