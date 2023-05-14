// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import CoreBluetooth
import UIKit

struct WhisperData {
    // MARK: Preferences
    static func userName() -> String {
        let defaults = UserDefaults.standard
        let name = defaults.string(forKey: "device_name_preference") ?? ""
        return name
    }
    static func updateDeviceName(_ name: String) {
        let defaults = UserDefaults.standard
        defaults.setValue(name, forKey: "device_name_preference")
    }
    static func requireAuthentication() -> Bool {
        let defaults = UserDefaults.standard
        let result = defaults.bool(forKey: "listener_authentication_preference")
        return result
    }
    static func alertSound() -> String {
        let defaults = UserDefaults.standard
        return defaults.string(forKey: "alert_sound_preference") ?? "bike-horn"
    }
    
    // MARK: UUIDs
    static var deviceId: String = {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "local_device_id") {
            return id
        } else {
            let id = randomString(length: 8)
            defaults.setValue(id, forKey: "local_device_id")
            return id
        }
    }()
    static let whisperNameUuid = CBUUID(string: "392E137A-D692-4CBC-882A-9D4A81C5CDDB")
    static let listenNameUuid = CBUUID(string: "246FB297-3AED-4B08-A231-47EFC4EEFD4D")
    static let textUuid = CBUUID(string: "11A7087A-26F1-47C7-AD1B-6B4BC4930628")
    static let spareUuid = CBUUID(string: "6048A326-0F6F-4744-9C7A-A9796C8C7748")
    static let disconnectUuid = CBUUID(string: "235FC59C-9DC4-4758-B8F0-3E25CB017F45")
    static let whisperServiceUuid = CBUUID(string: "6284331A-48F1-4E96-BD5C-97791DBA9FE5")
    static let listenServiceUuid = CBUUID(string: "FEEFEB67-2CC4-409C-B77B-540DD72F1848")
    
    // MARK: Characteristics
    static func listenNameCharacteristic() -> CBMutableCharacteristic {
        var props: CBCharacteristicProperties = .write
        var perms: CBAttributePermissions = .writeable
        if requireAuthentication() {
            props = [.write, .authenticatedSignedWrites]
            perms = .writeEncryptionRequired
        }
        return CBMutableCharacteristic(type: listenNameUuid, properties: props, value: nil, permissions: perms)
    }
    static var whisperNameCharacteristic = CBMutableCharacteristic(
        type: whisperNameUuid, properties: .read, value: nil, permissions: .readable)
    static var whisperTextCharacteristic = CBMutableCharacteristic(
        type: textUuid, properties: [.read, .notify], value: nil, permissions: .readable)
    static var whisperDisconnectCharacteristic = CBMutableCharacteristic(
        type: disconnectUuid, properties: [.read, .notify], value: nil, permissions: [.readable])

    // MARK: Services
    static func whisperService() -> CBMutableService {
        let service = CBMutableService(type: whisperServiceUuid, primary: true)
        service.characteristics = [
            whisperNameCharacteristic,
            whisperTextCharacteristic,
            whisperDisconnectCharacteristic,
            listenNameCharacteristic(),
        ]
        return service
    }
    
    // MARK: helpers
    static func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789~!@#$%^&*()_+`-={}[]"
        return String((0..<length).map{ _ in letters.randomElement()! })
    }
}
