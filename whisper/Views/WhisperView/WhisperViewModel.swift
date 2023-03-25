// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Combine
import CoreBluetooth

final class WhisperViewModel: ObservableObject {
    @Published var statusText: String = ""
    var pastText: PastTextViewModel = .init()

    private var liveText: String = ""
    private var pendingChunks: [TextProtocol.ProtocolChunk] = []
    private var advertisingInProgress = false
    private var manager = BluetoothManager.shared
    private var cancellables: Set<AnyCancellable> = []
    private var listeners: Set<String> = []
    
    init() {
        manager.peripheralSubject
            .sink { [weak self] in self?.noticeAdvertisement($0) }
            .store(in: &cancellables)
        manager.centralSubscribedSubject
            .sink { [weak self] in self?.noticeSubscription($0) }
            .store(in: &cancellables)
        manager.centralUnsubscribedSubject
            .sink { [weak self] in self?.noticeUnsubscription($0) }
            .store(in: &cancellables)
        manager.readRequestSubject
            .sink { [weak self] in self?.processReadRequest($0) }
            .store(in: &cancellables)
        manager.readyToUpdateSubject
            .sink { [weak self] in self?.processReadyToUpdate($0) }
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
    
    /// Receive an updated live text from the view.
    /// Returns whether or not to reset the live text to empty.
    func updateLiveText(old: String, new: String) {
        liveText = new
        if let chunk = TextProtocol.diffLines(old: old, new: new) {
            pendingChunks.append(chunk)
            updateListeners()
        }
    }
    
    /// User has submitted the live text
    func submitLiveText() {
        pastText.addLine(liveText)
        liveText = ""
        pendingChunks.append(TextProtocol.ProtocolChunk.completionChunk())
        updateListeners()
    }
    
    /// update listeners on changes in live text
    func updateListeners() {
        guard !listeners.isEmpty else {
            print("No listeners to update, ignoring process update")
            return
        }
        guard !pendingChunks.isEmpty else {
            print("Nothing to update listeners with")
            return
        }
        print("Updating subscribed listeners...")
        while !pendingChunks.isEmpty {
            let chunk = pendingChunks.first!
            let sendOk = manager.updateValue(value: chunk.toData(),
                                             characteristic: WhisperData.whisperLiveTextCharacteristic)
            if sendOk {
                pendingChunks.removeFirst()
            } else {
                break
            }
        }
    }
    
    private func find_listener() {
        print("Advertising whisperer...")
        manager.advertise(service: WhisperData.whisperServiceUuid)
        advertisingInProgress = true
        refreshStatusText()
    }
    
    private func stop_find_listener() {
        print("Stop advertising whisperer...")
        manager.stopAdvertising(service: WhisperData.whisperServiceUuid)
        advertisingInProgress = false
        refreshStatusText()
    }
    
    func refreshStatusText() {
        let maybeLooking = advertisingInProgress ? ", looking for more..." : ""
        if advertisingInProgress && listeners.isEmpty {
            statusText = "Looking for listeners..."
        } else if listeners.count == 1 {
            statusText = "Whispering to 1 listener\(maybeLooking)"
        } else {
            statusText = "Whispering to \(listeners.count) listeners\(maybeLooking)"
        }
    }
    
    private func addListener(_ central: CBCentral) {
        let (inserted, _) = listeners.insert(central.identifier.uuidString)
        if inserted {
            print("Found listener \(central)")
            stop_find_listener()
        }
        refreshStatusText()
    }
    
    private func removeListener(_ central: CBCentral) {
        if listeners.remove(central.identifier.uuidString) != nil {
            print("Lost listener \(central)")
            if listeners.isEmpty {
                find_listener()
            }
        }
        refreshStatusText()
    }
    
    private func noticeAdvertisement(_ pair: (CBPeripheral, [String: Any])) {
        if let uuids = pair.1[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            if uuids.contains(WhisperData.listenServiceUuid) {
                debugPrint("Heard from listener \(pair.0) with ad \(pair.1)")
                find_listener()
            }
        }
    }
    
    private func noticeSubscription(_ pair: (CBCentral, CBCharacteristic)) {
        addListener(pair.0)
    }
    
    private func noticeUnsubscription(_ pair: (CBCentral, CBCharacteristic)) {
        removeListener(pair.0)
    }
    
    private func processReadRequest(_ request: CBATTRequest) {
        print("Received read request \(request)...")
        addListener(request.central)
        let characteristic = request.characteristic
        var responseData: Data? = nil
        if characteristic.uuid == WhisperData.whisperNameUuid {
            print("Request is for name")
            responseData = Data(WhisperData.deviceName.utf8)
        } else if characteristic.uuid == WhisperData.whisperLiveTextUuid {
            print("Request is for live text")
            // the requesting whisperer should replace their liveText with ours
            let chunk = TextProtocol.ProtocolChunk(start: 0, text: liveText)
            responseData = chunk.toData()
        } else if characteristic.uuid == WhisperData.whisperPastTextUuid {
            print("Request is for past text")
            responseData = Data(pastText.getAsText().utf8)
        }
        if let responseData = responseData {
            if request.offset > responseData.count {
                manager.respondToReadRequest(request: request, withCode: .invalidOffset)
            } else {
                let subData = responseData.subdata(in: request.offset ..< responseData.count)
                request.value = subData
                manager.respondToReadRequest(request: request, withCode: .success)
            }
        } else {
            print("Got a read request for an unexpected characteristic: \(characteristic)")
            manager.respondToReadRequest(request: request, withCode: .attributeNotFound)
        }
    }
    
    private func processReadyToUpdate(_ ignore: ()) {
        updateListeners()
    }
}
