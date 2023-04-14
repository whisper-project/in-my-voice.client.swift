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
    private var directedChunks: [CBCentral: [TextProtocol.ProtocolChunk]] = [:]
    private var advertisingInProgress = false
    private var manager = BluetoothManager.shared
    private var cancellables: Set<AnyCancellable> = []
    private var listenAdvertisers: [String: String] = [:]
    private var listeners: Set<String> = []
    
    init() {
        manager.peripheralSubject
            .sink { [weak self] in self?.noticeListener($0) }
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
        // look for listeners who are looking for us
        manager.scan(forServices: [WhisperData.listenServiceUuid], allow_repeats: true)
        refreshStatusText()
    }
    
    func stop() {
        manager.stopScan()
        stopAdvertising()
        listeners.removeAll()
        manager.unpublish(service: WhisperData.whisperService)
    }
    
    func sendAllText(listener: CBCentral) {
        guard directedChunks[listener] == nil else {
            logger.log("Read already in progress for listener \(listener)")
            return
        }
        var chunks = pastText.getLines().map{TextProtocol.ProtocolChunk.fromPastText(text: $0)}
        chunks.append(TextProtocol.ProtocolChunk.fromLiveText(text: liveText))
        directedChunks[listener] = chunks
        updateListeners()
    }
    
    /// Receive an updated live text from the view.
    /// Returns the new live text the view should display.
    func updateLiveText(old: String, new: String) -> String {
        guard old != new else {
            return liveText
        }
        let chunks = TextProtocol.diffLines(old: old, new: new)
        for chunk in chunks {
            pendingChunks.append(chunk)
            if chunk.isCompleteLine() {
                pastText.addLine(liveText)
                liveText = ""
            } else {
                liveText = TextProtocol.applyDiff(old: liveText, chunk: chunk)
            }
        }
        updateListeners()
        return liveText
    }
    
    func playSound() {
        let soundName = WhisperData.alertSound()
        let chunk = TextProtocol.ProtocolChunk.sound(soundName)
        pendingChunks.append(chunk)
        updateListeners()
    }
    
    /// User has submitted the live text
    func submitLiveText() -> String {
        return self.updateLiveText(old: liveText, new: liveText + "\n")
    }
    
    /// update listeners on changes in live text
    func updateListeners() {
        guard !listeners.isEmpty else {
            logger.debug("No listeners to update, dumping pending changes")
            pendingChunks.removeAll()
            return
        }
        // prioritize readers over subscribers, because we want to hold
        // the changes to live text until the readers are caught up
        if !directedChunks.isEmpty {
            logger.log("Updating reading listeners...")
            while let (listener, chunks) = directedChunks.first {
                while let chunk = chunks.first {
                    let sendOk = manager.updateValue(value: chunk.toData(),
                                                     characteristic: WhisperData.whisperTextCharacteristic,
                                                     central: listener)
                    if sendOk {
                        if chunks.count == 1 {
                            directedChunks.removeValue(forKey: listener)
                        } else {
                            directedChunks[listener]!.removeFirst()
                        }
                    } else {
                        return
                    }
                }
            }
        } else if !pendingChunks.isEmpty {
            logger.debug("Updating subscribed listeners...")
            while let chunk = pendingChunks.first {
                let sendOk = manager.updateValue(value: chunk.toData(),
                                                 characteristic: WhisperData.whisperTextCharacteristic)
                if sendOk {
                    pendingChunks.removeFirst()
                } else {
                    return
                }
            }
        }
    }
    
    private func startAdvertising() {
        guard !advertisingInProgress else {
            return
        }
        logger.log("Advertising whisperer...")
        manager.advertise(services: [WhisperData.whisperServiceUuid])
        advertisingInProgress = true
    }
    
    private func stopAdvertising() {
        logger.log("Stop advertising whisperer")
        manager.stopAdvertising()
        listenAdvertisers.removeAll()
        advertisingInProgress = false
    }
    
    func refreshStatusText() {
        let maybeLooking = advertisingInProgress ? ", looking for \(listenAdvertisers.count - listeners.count) more..." : ""
        if listeners.isEmpty {
            if advertisingInProgress {
                statusText = "Looking for listeners..."
            } else {
                statusText = "No listeners yet, but you can type"
            }
        } else if listeners.count == 1 {
            statusText = "Whispering to 1 listener\(maybeLooking)"
        } else {
            statusText = "Whispering to \(listeners.count) listeners\(maybeLooking)"
        }
    }
    
    private func addListener(_ central: CBCentral) {
        let uuidString = central.identifier.uuidString
        guard !listeners.contains(uuidString) else {
            // we've already connected this listener
            return
        }
        listeners.insert(uuidString)
        if listenAdvertisers.count <= listeners.count {
            logger.log("Connected as many listeners as were advertising")
            stopAdvertising()
        }
        refreshStatusText()
    }
    
    private func removeListener(_ central: CBCentral) {
        if listeners.remove(central.identifier.uuidString) != nil {
            logger.log("Lost\(self.listeners.isEmpty ? " last" : "") listener \(central)")
        }
        refreshStatusText()
    }
    
    private func noticeListener(_ pair: (CBPeripheral, [String: Any])) {
        let uuidString = pair.0.identifier.uuidString
        if let uuids = pair.1[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            if uuids.contains(WhisperData.listenServiceUuid) {
                if let localName = listenAdvertisers[uuidString] {
                    logger.debug("Ignoring repeat ad from already-pending listener \(uuidString) with name \(localName)")
                } else {
                    var name = "(no name)"
                    if let adName = pair.1[CBAdvertisementDataLocalNameKey],
                       let localName = adName as? String {
                        name = localName
                    }
                    listenAdvertisers[uuidString] = name
                    logger.debug("Got first ad from listener \(uuidString) with name \(name)")
                    startAdvertising()
                }
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
        logger.log("Received read request \(request)...")
        guard request.offset == 0 else {
            logger.log("Read request has non-zero offset, ignoring it")
            manager.respondToReadRequest(request: request, withCode: .invalidOffset)
            return
        }
        addListener(request.central)
        let characteristic = request.characteristic
        if characteristic.uuid == WhisperData.whisperNameUuid {
            logger.log("Request is for name")
            request.value = Data(WhisperData.deviceName.utf8)
            manager.respondToReadRequest(request: request, withCode: .success)
        } else if characteristic.uuid == WhisperData.whisperTextUuid {
            logger.log("Request is for live text")
            request.value = TextProtocol.ProtocolChunk.acknowledgeRead().toData()
            manager.respondToReadRequest(request: request, withCode: .success)
            sendAllText(listener: request.central)
        } else {
            logger.error("Got a read request for an unexpected characteristic: \(characteristic)")
            manager.respondToReadRequest(request: request, withCode: .attributeNotFound)
        }
    }
    
    private func processReadyToUpdate(_ ignore: ()) {
        updateListeners()
    }
}
