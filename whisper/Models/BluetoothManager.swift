// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Combine
import CoreBluetooth
import UIKit

final class BluetoothManager: NSObject {
    static let shared: BluetoothManager = .init()
        
    var stateSubject: CurrentValueSubject<CBManagerState, Never> = .init(.unknown)
    var peripheralSubject: PassthroughSubject<(CBPeripheral, [String: Any]), Never> = .init()
    var servicesSubject: PassthroughSubject<CBService, Never> = .init()
    var characteristicsSubject: PassthroughSubject<(CBService, [CBCharacteristic]), Never> = .init()
    
    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    
    private var current_state: CBManagerState!
    private var wanted_services: Set<CBUUID> = []
    private var advertised_services: Set<CBUUID> = []
    
    override init() {
        super.init()
        centralManager = .init(delegate: self, queue: .main)
        peripheralManager = .init(delegate: self, queue: .main)
        current_state = centralManager.state
        stateSubject.send(current_state)
    }
    
    func scan(forService: CBUUID) {
        wanted_services.insert(forService)
        scan_for_services()
    }
    
    func stopScan(forService: CBUUID) {
        wanted_services.remove(forService)
        scan_for_services()
    }
    
    private func scan_for_services() {
        if wanted_services.isEmpty {
            centralManager.stopScan()
        } else {
            centralManager.scanForPeripherals(withServices: Array(wanted_services))
        }
    }
    
    func advertise(service: CBUUID) {
        advertised_services.insert(service)
        advertise_services()
    }
    
    func stopAdvertising(service: CBUUID) {
        advertised_services.remove(service)
        advertise_services()
    }
    
    private func advertise_services() {
        if advertised_services.isEmpty {
            peripheralManager.stopAdvertising()
        } else {
            peripheralManager.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: Array(advertised_services),
                CBAdvertisementDataLocalNameKey: WhisperData.deviceName
            ])
        }
    }
    
    func connect(_ peripheral: CBPeripheral) {
        centralManager.stopScan()
        peripheral.delegate = self
        centralManager.connect(peripheral)
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != current_state {
            current_state = central.state
            stateSubject.send(central.state)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        peripheralSubject.send((peripheral, advertisementData))
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(Array(wanted_services))
    }
}

extension BluetoothManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state != current_state {
            current_state = peripheral.state
            stateSubject.send(peripheral.state)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let err = error {
            print("Add \(service) failed with \(err)")
            fatalError("Couldn't add the service \(service.uuid) - please report a bug!")
        }
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else {
            return
        }
        for service in services {
            if wanted_services.contains(service.uuid) {
                servicesSubject.send(service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else {
            return
        }
        characteristicsSubject.send((service, characteristics))
    }
}
