// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Combine
import CoreBluetooth

let connectingLiveText = "This is where the line being typed by the whisperer will appear in real time... "
let connectingPastText = "The most recent line will be on top.\nThis is where lines will move after the whisperer hits return."
let unknownWhispererName = "(not yet known)"

final class ListenViewModel: ObservableObject {
    @Published var statusText: String = ""
    @Published var liveText: String = ""
    @Published var pastText: String = ""
    
    private var manager = BluetoothManager.shared
    private var cancellables: Set<AnyCancellable> = []
    private var whisperer: CBPeripheral?
    private var whispererName: String = unknownWhispererName
    private var nameCharacteristic: CBCharacteristic?
    private var liveTextCharacteristic: CBCharacteristic?
    private var pastTextCharacteristic: CBCharacteristic?
    private var disconnectCharacteristic: CBCharacteristic?
    private var scanInProgress: Bool = false
    private var resetInProgress: Bool = false

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
        manager.receivedValueSubject
            .sink{ [weak self] in self?.readValue($0) }
            .store(in: &cancellables)
        manager.disconnectedSubject
            .sink{ [weak self] in self?.wasDisconnected($0) }
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
            liveText = ""
            pastText = ""
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
                [
                    WhisperData.whisperNameUuid,
                    WhisperData.whisperLiveTextUuid,
                    WhisperData.whisperPastTextUuid,
                    WhisperData.whisperDisconnectUuid,
                ],
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
        print("Readying whisperer \(whisperer!)...")
        let allCs = service.characteristics!
        if let nameC = allCs.first(where: { $0.uuid == WhisperData.whisperNameUuid }) {
            nameCharacteristic = nameC
            whisperer?.readValue(for: nameCharacteristic!)
        } else {
            fatalError("Whisper service has no name characteristic: report a bug!")
        }
        if let pastTextC = allCs.first(where: { $0.uuid == WhisperData.whisperPastTextUuid }) {
            pastTextCharacteristic = pastTextC
            whisperer?.readValue(for: pastTextCharacteristic!)
        } else {
            fatalError("Whisper service has no past text characteristic: report a bug!")
        }
        if let liveTextC = allCs.first(where: { $0.uuid == WhisperData.whisperLiveTextUuid }) {
            liveTextCharacteristic = liveTextC
            whisperer!.readValue(for: liveTextCharacteristic!)
            whisperer!.setNotifyValue(true, for: liveTextCharacteristic!)
        } else {
            fatalError("Whisper service has no live text characteristic: report a bug!")
        }
        if let disconnectC = allCs.first(where: { $0.uuid == WhisperData.whisperDisconnectUuid }) {
            disconnectCharacteristic = disconnectC
            whisperer!.setNotifyValue(true, for: disconnectC)
        } else {
            fatalError("Whisper service has no disconnect characteristic: report a bug!")
        }
        // TODO: read PastTextCharacteristic
        stopFindWhisperer(connectComplete: true)
    }
    
    private func readValue(_ pair: (CBPeripheral, CBCharacteristic)) {
        guard pair.0 == whisperer else {
            fatalError("Received a read value from unexpected peripheral \(pair.0)")
        }
        let characteristic = pair.1
        if characteristic.uuid == nameCharacteristic?.uuid {
            print("Received name value from whisperer")
            if let nameData = characteristic.value {
                if nameData.isEmpty {
                    whispererName = "(anonymous)"
                } else {
                    whispererName = String(decoding: nameData, as: UTF8.self)
                }
                statusText = "Listening to \(whispererName)"
            }
        } else if characteristic.uuid == liveTextCharacteristic?.uuid {
            print("Received live text value from whisperer")
            if let textData = characteristic.value,
               let chunk = TextProtocol.ProtocolChunk.fromData(textData) {
                if chunk.start == 0 {
                    // a full read does a reset
                    resetInProgress = false
                    liveText = chunk.text
                } else if chunk.start > liveText.count {
                    // we must have missed a packet, read the full state to reset
                    // unless we're already waiting for the read to return
                    if !resetInProgress {
                        whisperer!.readValue(for: liveTextCharacteristic!)
                        resetInProgress = true
                    }
                } else {
                    let nextText = TextProtocol.applyDiff(old: liveText, chunk: chunk)
                    if nextText.hasSuffix("\n") {
                        liveText = ""
                        pastText = nextText + pastText
                    } else {
                        liveText = nextText
                    }
                }
            }
        } else if characteristic.uuid == pastTextCharacteristic?.uuid {
            print("Received past text value from whisperer")
            if let textData = characteristic.value {
                if !textData.isEmpty {
                    pastText = pastText + String(decoding: textData, as: UTF8.self)
                }
            }
        } else if characteristic.uuid == disconnectCharacteristic?.uuid {
            print("Received disconnect from whisperer")
            disconnect()
        } else {
            print("Got a received value notification for an unexpected characteristic: \(characteristic)")
        }
    }
    
    private func wasDisconnected(_ peripheral: CBPeripheral) {
        guard peripheral == whisperer else {
            print("Received disconnect from \(peripheral) while connected to \(String(describing: whisperer))")
            return
        }
        print("Whisperer disconnected")
        manager.disconnect(whisperer!)
        disconnectCharacteristic = nil
        nameCharacteristic = nil
        pastTextCharacteristic = nil
        pastText = connectingPastText
        liveTextCharacteristic = nil
        liveText = connectingLiveText
        whispererName = unknownWhispererName
        whisperer = nil
        findWhisperer()
    }
    
    private func disconnect() {
        stopFindWhisperer(connectComplete: true)
        if let liveTextC = liveTextCharacteristic {
            whisperer!.setNotifyValue(false, for: liveTextC)
            liveTextCharacteristic = nil
            liveText = connectingLiveText
        }
        if let disconnectC = disconnectCharacteristic {
            whisperer!.setNotifyValue(false, for: disconnectC)
            disconnectCharacteristic = nil
        }
        if let whisperP = whisperer {
            manager.disconnect(whisperP)
            whisperer = nil
            whispererName = unknownWhispererName
            nameCharacteristic = nil
            pastTextCharacteristic = nil
            pastText = connectingPastText
        }
        statusText = "Stopped listening"
    }
}
