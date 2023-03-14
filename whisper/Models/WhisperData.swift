// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import CoreBluetooth
import UIKit

struct WhisperData {
    static let whisperServiceUuid = CBUUID(string: "6284331A-48F1-4E96-BD5C-97791DBA9FE5")
    static let whisperNameUuid = CBUUID(string: "392E137A-D692-4CBC-882A-9D4A81C5CDDB")
    static let whisperPastTextUuid = CBUUID(string: "6048A326-0F6F-4744-9C7A-A9796C8C7748")
    static let whisperLiveTextUuid = CBUUID(string: "11A7087A-26F1-47C7-AD1B-6B4BC4930628")
    // static let whisperNextTextUuid = CBUUID(string: "235FC59C-9DC4-4758-B8F0-3E25CB017F45")
    static let listenServiceUuid = CBUUID(string: "FEEFEB67-2CC4-409C-B77B-540DD72F1848")
    static let listenNameUuid = CBUUID(string: "246FB297-3AED-4B08-A231-47EFC4EEFD4D")
    static let deviceName = UIDevice.current.name

    static var listenNameCharacteristic = CBMutableCharacteristic(
        type: listenNameUuid, properties: .read, value: Data(deviceName.utf8), permissions: .readable)
    static var whisperNameCharacteristic = CBMutableCharacteristic(
        type: whisperNameUuid, properties: .read, value: Data(deviceName.utf8), permissions: .readable)
    static var whisperPastTextCharacteristic = CBMutableCharacteristic(
        type: whisperPastTextUuid, properties: .read, value: nil, permissions: .readable)
    static var whisperLiveTextCharacteristic = CBMutableCharacteristic(
        type: whisperLiveTextUuid, properties: .notify, value: nil, permissions: .readable)

    static var listenService: CBMutableService = {
        let service = CBMutableService(type: listenServiceUuid, primary: true)
        service.characteristics = [listenNameCharacteristic]
        return service
    }()
    static var whisperService: CBMutableService = {
        let service = CBMutableService(type: whisperServiceUuid, primary: true)
        service.characteristics = [whisperNameCharacteristic, whisperPastTextCharacteristic, whisperLiveTextCharacteristic]
        return service
    }()
}
