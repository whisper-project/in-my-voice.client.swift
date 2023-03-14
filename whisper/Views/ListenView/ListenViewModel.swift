// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Combine
import CoreBluetooth

let connectingLiveText = "This is where the line being typed by the whisperer will appear in real time... "
let connectingPastText = "The most recent line will be on top.\nThis is where lines will move after the whisperer hits return."

final class ListenViewModel: ObservableObject {
    @Published var statusText: String = ""
    @Published var liveText: String = ""
    @Published var pastText: String = ""
    
    private var manager = BluetoothManager.shared
    private var cancellables: Set<AnyCancellable> = []
    private var whisperer: CBPeripheral?
    private var whispererName: String = "(not yet implemented)"
    private var liveTextCharacteristic: CBCharacteristic?
    private var scanInProgress: Bool = false
    private var liveTextBuffer = String()
    private var pastTextBuffer = String()

    init() {
        manager.peripheralSubject
            .sink{ [weak self] in self?.foundWhisperer($0) }
            .store(in: &cancellables)
        manager.servicesSubject
            .sink{ [weak self] in self?.connectedWhisperer($0) }
            .store(in: &cancellables)
        manager.characteristicsSubject
            .sink{ [weak self] in self?.whispererReady($0) }
            .store(in: &cancellables)
    }
    
    deinit {
        cancellables.cancel()
    }
    
    func start() {
        findWhisperer()
    }
    
    func stop() {
        disconnect()
    }
    
    private func findWhisperer() {
        guard whisperer == nil else {
            print("Tried to find a whisperer when we have one, ignoring request")
            return
        }
        statusText = "Looking for a whisperer to listen to…"
        liveText = connectingLiveText
        pastText = connectingPastText
        if !scanInProgress {
            scanInProgress = true
            print("Advertising listener and scanning for whisperer...")
            manager.scan(forService: WhisperData.whisperServiceUuid)
            manager.advertise(service: WhisperData.listenServiceUuid)
        }
    }
    
    private func stopFindWhisperer(connectComplete: Bool) {
        if scanInProgress {
            scanInProgress = false
            print("Stop advertising listener and scanning for whisperer")
            manager.stopScan(forService: WhisperData.whisperServiceUuid)
            manager.stopAdvertising(service: WhisperData.listenServiceUuid)
        }
        if connectComplete {
            statusText = "Listening to \(whispererName)"
            liveText = liveTextBuffer
            pastText = pastTextBuffer
        }
    }
    
    private func foundWhisperer(_ pair: (CBPeripheral, [String: Any])) {
        stopFindWhisperer(connectComplete: false)
        guard whisperer == nil else {
            print("Already have a whisperer, won't connect to \(pair.0) with ad \(pair.1)")
            return
        }
        if let uuids = pair.1[CBAdvertisementDataServiceUUIDsKey] as? Array<CBUUID> {
            if uuids.contains(WhisperData.whisperServiceUuid) {
                print("Connecting to whisperer \(pair.0) with ad \(pair.1)")
                whisperer = pair.0
                manager.connect(whisperer!)
            }
        }
    }

    private func connectedWhisperer(_ pair: (CBPeripheral, [CBService])) {
        guard pair.0 == whisperer else {
            if let requested = whisperer {
                fatalError("Connected to whisperer \(pair.0) but requested connection to \(requested)")
            } else {
                fatalError("Connected to whisperer \(pair.0) but didn't request a connection")
            }
        }
        if let whisperSvc = pair.1.first(where: {svc in svc.uuid == WhisperData.whisperServiceUuid}) {
            print("Connected to whisperer \(whisperer!) with service \(pair.1), readying...")
            whisperer!.discoverCharacteristics(
                [WhisperData.whisperNameUuid, WhisperData.whisperLiveTextUuid, WhisperData.whisperPastTextUuid],
                for: whisperSvc
            )
        } else {
            fatalError("Connected to advertised whisperer \(whisperer!) but it has no whisper service")
        }
    }
    
    private func whispererReady(_ service: CBService) {
        guard service.characteristics != nil else {
            fatalError("Readied whisper service with no characteristics: report a bug!")
        }
        let allCs = service.characteristics!
        if let nameC = allCs.first(where: { $0.uuid == WhisperData.whisperNameUuid }) {
            if let nameData = nameC.value, !nameData.isEmpty {
                whispererName = String(decoding: nameData, as: UTF8.self)
            }
            print("Readying whisperer with name '\(whispererName)'...")
        } else {
            fatalError("Whisper service has no name characteristic: report a bug!")
        }
        if let liveTextC = allCs.first(where: { $0.uuid == WhisperData.whisperLiveTextUuid }) {
            liveTextCharacteristic = liveTextC
            whisperer!.setNotifyValue(true, for: liveTextC)
        } else {
            fatalError("Whisper service has no live text characteristic: report a bug!")
        }
        // TODO: read PastTextCharacteristic
        stopFindWhisperer(connectComplete: true)
    }
    
    private func disconnect() {
        stopFindWhisperer(connectComplete: true)
        if let liveTextC = liveTextCharacteristic {
            whisperer!.setNotifyValue(false, for: liveTextC)
        }
        if let whisperer = whisperer {
            manager.disconnect(whisperer)
        }
    }
}
