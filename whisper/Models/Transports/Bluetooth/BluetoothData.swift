// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import CoreBluetooth

struct BluetoothData {
    // MARK: UUIDs
    static let contentOutUuid = CBUUID(string: "DD7A0B07-C618-4FC0-823E-3D01899EB697")
    static let contentInUuid = CBUUID(string: "C14FC58F-5E4C-4D83-A9B2-781C0413B9C6")
    static let controlOutUuid = CBUUID(string: "270E4080-09CD-4E69-A23A-564661045D56")
    static let controlInUuid = CBUUID(string: "FAADF8DD-DA86-4659-ACF7-8253A6F3B7A3")
    static let whisperServiceUuid = CBUUID(string: "2583870B-59EB-4526-9ADE-CD037E24DE17")
    static let listenServiceUuid = CBUUID(string: "1A4DCFF2-A3E8-47E7-BC16-99C8AFD05934")

    // MARK: Characteristics
    static let contentOutCharacteristic = CBMutableCharacteristic(
        type: contentOutUuid, properties: [.read, .notify], value: nil, permissions: .readable)
    static let contentInCharacteristic = CBMutableCharacteristic(
        type: contentInUuid, properties: .write, value: nil, permissions: .writeable)
    static let controlOutCharacteristic = CBMutableCharacteristic(
        type: controlOutUuid, properties: [.read, .notify], value: nil, permissions: .readable)
    static let controlInCharacteristic = CBMutableCharacteristic(
		type: controlInUuid, properties: [.write, .writeWithoutResponse], value: nil, permissions: .writeable)

    // MARK: Services
    static func whisperService() -> CBMutableService {
        let service = CBMutableService(type: whisperServiceUuid, primary: true)
        service.characteristics = [
            contentOutCharacteristic,
            contentInCharacteristic,
            controlOutCharacteristic,
            controlInCharacteristic,
        ]
        return service
    }
    
    // MARK: helpers
	static func deviceId(_ uuidString: String) -> String {
		return String(uuidString.prefix(8))
    }
}
