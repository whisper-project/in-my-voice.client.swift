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
    var servicesSubject: PassthroughSubject<(CBPeripheral, [CBService]), Never> = .init()
    var characteristicsSubject: PassthroughSubject<CBService, Never> = .init()
    var centralSubscribedSubject: PassthroughSubject<(CBCentral, CBCharacteristic), Never> = .init()
    var centralUnsubscribedSubject: PassthroughSubject<(CBCentral, CBCharacteristic), Never> = .init()
    var readRequestSubject: PassthroughSubject<CBATTRequest, Never> = .init()
    var readyToUpdateSubject: PassthroughSubject<(), Never> = .init()
    var receivedValueSubject: PassthroughSubject<(CBPeripheral, CBCharacteristic), Never> = .init()
    var disconnectedSubject: PassthroughSubject<CBPeripheral, Never> = .init()

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    
    private var current_state: CBManagerState!
    private var advertised_services: [CBUUID] = []
    
    override init() {
        super.init()
        centralManager = .init(delegate: self, queue: .main)
        peripheralManager = .init(delegate: self, queue: .main)
        current_state = centralManager.state
        stateSubject.send(current_state)
    }
    
    func scan(forServices: [CBUUID], allow_repeats: Bool = false) {
        guard !forServices.isEmpty else {
            fatalError("Can't scan for no services")
        }
        centralManager.scanForPeripherals(
            withServices: forServices,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: allow_repeats as NSNumber]
        )
    }
    
    func stopScan() {
        centralManager.stopScan()
    }
    
    func publish(service: CBMutableService) {
        peripheralManager.add(service)
    }
    
    func unpublish(service: CBMutableService) {
        peripheralManager.remove(service)
    }
    
    func unpublishAll() {
        peripheralManager.removeAllServices()
    }
    
    func advertise(services: [CBUUID], localName: String = WhisperData.deviceName) {
        guard !services.isEmpty else {
            fatalError("Can't advertise no services")
        }
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: services,
            CBAdvertisementDataLocalNameKey: localName,
        ])
    }
    
    func stopAdvertising() {
        peripheralManager.stopAdvertising()
    }
    
    func connect(_ peripheral: CBPeripheral) {
        peripheral.delegate = self
        centralManager.connect(peripheral)
    }
    
    func disconnect(_ peripheral: CBPeripheral) {
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    func respondToReadRequest(request: CBATTRequest, withCode: CBATTError.Code) {
        peripheralManager.respond(to: request, withResult: withCode)
    }
    
    func updateValue(value: Data, characteristic: CBMutableCharacteristic) -> Bool {
        return peripheralManager.updateValue(value, for: characteristic, onSubscribedCentrals: nil)
    }
    
    func updateValue(value: Data, characteristic: CBMutableCharacteristic, central: CBCentral) -> Bool {
        return peripheralManager.updateValue(value, for: characteristic, onSubscribedCentrals: [central])
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
        peripheral.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let err = error {
            print("Failed to disconnect peripheral \(peripheral): \(err)")
            return
        }
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
            fatalError("Couldn't add the service \(service) - please report a bug!")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        centralSubscribedSubject.send((central, characteristic))
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        centralUnsubscribedSubject.send((central, characteristic))
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        readRequestSubject.send(request)
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        readyToUpdateSubject.send(())
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let err = error {
            print("Error discovering services for \(peripheral): \(err)")
            return
        }
        servicesSubject.send((peripheral, peripheral.services ?? []))
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let err = error {
            print("Error discovering characteristics for \(service) on \(peripheral): \(err)")
            return
        }
        characteristicsSubject.send(service)
    }
        
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error {
            print("Error retrieving value for \(characteristic) on \(peripheral): \(err)")
            return
        }
        receivedValueSubject.send((peripheral, characteristic))
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error {
            print("Error subscribing or unsubscribing to \(characteristic) on \(peripheral): \(err)")
            return
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        print("Lost services \(invalidatedServices) from \(peripheral)")
        if invalidatedServices.first(where: { $0.uuid == WhisperData.whisperServiceUuid }) != nil {
            disconnectedSubject.send(peripheral)
        }
    }
}
