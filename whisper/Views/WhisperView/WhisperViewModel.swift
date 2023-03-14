// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Combine
import CoreBluetooth

final class WhisperViewModel: ObservableObject {
    @Published var statusText: String = ""
    @Published var liveText: String = ""
    @Published var pastText: String = ""
    
    private var manager = BluetoothManager.shared
    private var cancellables: Set<AnyCancellable> = []
    private var listeners: Set<CBCentral> = []
    
    init() {
        manager.peripheralSubject
            .sink{ [weak self] in self?.notice_listener($0) }
            .store(in: &cancellables)
        manager.centralSubscribedSubject
            .sink{ [weak self] in self?.add_listener($0) }
            .store(in: &cancellables)
        manager.centralUnsubscribedSubject
            .sink{ [weak self] in self?.remove_listener($0) }
            .store(in: &cancellables)
        manager.readRequestSubject
            .sink{ [weak self] in self?.process_read($0) }
            .store(in: &cancellables)
        manager.readyToUpdateSubject
                .sink{ [weak self] in self?.process_update($0) }
            .store(in: &cancellables)
    }
    
    deinit {
        cancellables.cancel()
    }
    
    func start() {
        manager.publish(service: WhisperData.whisperService)
        // make sure we notice listeners who come late
        manager.scan(forService: WhisperData.listenServiceUuid)
        find_listener()
    }
    
    func stop() {
        stop_find_listener()
        manager.stopScan(forService: WhisperData.listenServiceUuid)
        listeners.removeAll()
        manager.unpublish(service: WhisperData.whisperService)
    }
    
    private func find_listener() {
        if listeners.isEmpty {
            statusText = "Looking for listeners..."
        } else if listeners.count == 1 {
            statusText = "Whispering to 1 listener, looking for more..."
        } else {
            statusText = "Whispering to \(listeners.count) listeners, looking for more..."
        }
        print("Advertising whisperer...")
        manager.advertise(service: WhisperData.whisperServiceUuid)
    }
    
    private func stop_find_listener() {
        print("Stop advertising whisperer...")
        manager.stopAdvertising(service: WhisperData.whisperServiceUuid)
        if listeners.count == 1 {
            statusText = "Whispering to 1 listener"
        } else {
            statusText = "Whispering to \(listeners.count) listeners"
        }
    }
    
    private func notice_listener(_ pair: (CBPeripheral, [String: Any])) {
        if let uuids = pair.1[CBAdvertisementDataServiceUUIDsKey] as? Array<CBUUID> {
            if uuids.contains(WhisperData.listenServiceUuid) {
                debugPrint("Heard from listener \(pair.0) with ad \(pair.1)")
                find_listener()
            }
        }
    }
    
    private func add_listener(_ pair: (CBCentral, CBCharacteristic)) {
        guard pair.1.uuid == WhisperData.whisperLiveTextUuid else {
            fatalError("Added listener \(pair.0) with incorrect characteristic \(pair.1)")
        }
        listeners.insert(pair.0)
        print("Found listener \(pair.0)")
        stop_find_listener()
    }
    
    private func remove_listener(_ pair: (CBCentral, CBCharacteristic)) {
        guard pair.1.uuid == WhisperData.whisperLiveTextUuid else {
            fatalError("Removed listener \(pair.0) with incorrect characteristic \(pair.1)")
        }
        listeners.remove(pair.0)
        print("Lost listener \(pair.0)")
        if listeners.isEmpty {
            find_listener()
        }
    }
    
    private func process_read(_ request: CBATTRequest) {
        print("Received read request \(request)...")
    }
    
    private func process_update(_ ignore: ()) {
        guard !listeners.isEmpty else {
            print("No listeners to update, ignoring process update")
            return
        }
        print("Ready to update listeners...")
    }
}
