// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Combine
import CoreBluetooth

final class WhisperViewModel: ObservableObject {
    class Listener {
        var deviceId: String
        var name: String
        
        init(deviceId: String, name: String = "") {
            self.deviceId = deviceId
            self.name = name
        }
    }
    
    @Published var statusText: String = ""
    @Published var listeners: [CBCentral: Listener] = [:]
    var pastText: PastTextViewModel = .init()

    private var liveText: String = ""
    private var pendingChunks: [TextProtocol.ProtocolChunk] = []
    private var directedChunks: [CBCentral: [TextProtocol.ProtocolChunk]] = [:]
    private var advertisingInProgress = false
    private weak var adTimer: Timer?
    private var manager = BluetoothManager.shared
    private var cancellables: Set<AnyCancellable> = []
    private var candidates: [CBCentral: Listener] = [:]
    private var listenAdvertisers: [CBPeripheral: Listener] = [:]
    private var droppedListeners: [Listener] = []
    private var whisperService: CBMutableService?
    private var isInBackground = false

    init() {
        manager.peripheralSubject
            .sink { [weak self] in self?.noticeAd($0) }
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
        manager.writeRequestSubject
            .sink { [weak self] in self?.processWriteRequests($0) }
            .store(in: &cancellables)
        manager.readyToUpdateSubject
            .sink { [weak self] in self?.processReadyToUpdate($0) }
            .store(in: &cancellables)
    }
    
    deinit {
        cancellables.cancel()
    }
    
    // MARK: View entry points
    
    func start() {
        whisperService = WhisperData.whisperService()
        manager.publish(service: whisperService!)
        // look for listeners who are looking for us
        manager.scan(forServices: [WhisperData.listenServiceUuid], allow_repeats: true)
        startAdvertising()
        refreshStatusText()
    }
    
    func stop() {
        stopAdvertising()
        manager.stopScan()
        listeners.removeAll()
        if let service = whisperService {
            manager.unpublish(service: service)
            whisperService = nil
        }
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
    
    /// Drop a listener from the authorized list
    func dropListener(_ central: CBCentral) {
        guard let listener = listeners[central] else {
            logger.log("Ignoring drop request for non-listener: \(central)")
            return
        }
        logger.notice("Dropping listener \(listener.deviceId) (\(listener.name)): \(central)")
        // remember not to re-add this listener
        droppedListeners.append(listener)
        // tell this listener we've dropped it
        if !manager.updateValue(value: Data(), characteristic: WhisperData.whisperDisconnectCharacteristic, central: central) {
            logger.error("Drop message failed to central: \(central)")
        }
        removeListener(central)
    }
    
    /// Send an alert sound to a specific listener
    func alertListener(_ central: CBCentral) {
        guard listeners[central] != nil else {
            logger.log("Ignoring alert request for non-listener: \(central)")
            return
        }
        guard directedChunks[central] == nil else {
            logger.log("Can't alert while read in progress for: \(central)")
            return
        }
        let chunk = TextProtocol.ProtocolChunk.sound(WhisperData.alertSound())
        directedChunks[central] = [chunk]
        updateListeners()
    }
    
    func wentToBackground() {
        guard !isInBackground else {
            return
        }
        isInBackground = true
        stopAdvertising()
    }
    
    func wentToForeground() {
        guard isInBackground else {
            return
        }
        isInBackground = false
    }
    
    // MARK: Peripheral Event Handlers
    
    private func noticeAd(_ pair: (CBPeripheral, [String: Any])) {
        if let uuids = pair.1[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            if uuids.contains(WhisperData.listenServiceUuid) {
                if let listener = listenAdvertisers[pair.0] {
                    logger.debug("Ignoring repeat ad from already-pending listener \(listener.deviceId)")
                } else {
                    guard let adName = pair.1[CBAdvertisementDataLocalNameKey],
                          let deviceId = adName as? String else {
                        logger.error("Ignoring advertisement with no listener deviceId from \(pair.0)")
                        return
                    }
                    guard !droppedListeners.contains(where: { $0.deviceId == deviceId }) else {
                        logger.info("Ignoring advertisement from dropped listener \(deviceId)")
                        return
                    }
                    listenAdvertisers[pair.0] = Listener(deviceId: deviceId)
                    logger.debug("Got first ad from listener \(deviceId): \(pair.0)")
                    startAdvertising()
                }
            }
        }
    }
    
    private func noticeSubscription(_ pair: (CBCentral, CBCharacteristic)) {
        guard pair.1.uuid == WhisperData.textUuid || pair.1.uuid == WhisperData.disconnectUuid else {
            logger.error("Ignoring subscribe for unexpected characteristic: \(pair.1)")
            return
        }
        guard listeners[pair.0] == nil else {
            // this listener is already subscribed - nothing to do
            return
        }
        guard let candidate = candidates[pair.0] else {
            logger.error("Ignoring subscription request from non-candidate: \(pair.0)")
            return
        }
        logger.log("Candidate \(candidate.deviceId) (\(candidate.name)) has become a listener")
        listeners[pair.0] = candidate
        candidates.removeValue(forKey: pair.0)
        refreshStatusText()
    }
    
    private func noticeUnsubscription(_ pair: (CBCentral, CBCharacteristic)) {
        guard pair.1.uuid == WhisperData.whisperTextCharacteristic else {
            logger.error("Ignoring unsubscribe for unexpected characteristic: \(pair.1)")
            return
        }
        if let candidate = candidates.removeValue(forKey: pair.0) {
            logger.log("Dropping candidate \(candidate.deviceId): \(pair.0)")
        } else if listeners[pair.0] != nil {
            removeListener(pair.0)
        } else {
            logger.error("Ignoring unsubscription request from non-candidate, non-listener: \(pair.0)")
        }
    }
    
    private func processReadRequest(_ request: CBATTRequest) {
        logger.log("Received read request \(request)...")
        guard request.offset == 0 else {
            logger.log("Read request has non-zero offset, ignoring it")
            manager.respondToReadRequest(request: request, withCode: .invalidOffset)
            return
        }
        let characteristic = request.characteristic
        if characteristic.uuid == WhisperData.whisperNameUuid {
            logger.log("Request is for name")
            request.value = Data(WhisperData.deviceName.utf8)
            manager.respondToReadRequest(request: request, withCode: .success)
        } else if characteristic.uuid == WhisperData.textUuid {
            guard listeners[request.central] != nil else {
                logger.error("Refusing read text request from non-listener \(request.central)")
                manager.respondToReadRequest(request: request, withCode: .insufficientAuthorization)
                return
            }
            logger.log("Request is for complete text")
            request.value = TextProtocol.ProtocolChunk.acknowledgeRead().toData()
            manager.respondToReadRequest(request: request, withCode: .success)
            sendAllText(listener: request.central)
        } else if request.characteristic.uuid == WhisperData.disconnectUuid {
            if let candidate = candidates.removeValue(forKey: request.central) {
                logger.log("Dropping candidate \(candidate.deviceId): \(request.central)")
            } else if listeners[request.central] != nil {
                removeListener(request.central)
            } else {
                logger.error("Ignoring unsubscription request from non-candidate, non-listener: \(request.central)")
                return
            }
            request.value = Data()
            manager.respondToReadRequest(request: request, withCode: .success)
        } else {
            logger.error("Got a read request for an unexpected characteristic: \(characteristic)")
            manager.respondToReadRequest(request: request, withCode: .attributeNotFound)
        }
    }
    
    private func processWriteRequests(_ requests: [CBATTRequest]) {
        guard let request = requests.first else {
            fatalError("Got an empty write request sequence")
        }
        guard requests.count == 1 else {
            logger.error("Got multiple listener requests in a batch: \(requests)")
            manager.respondToWriteRequest(request: request, withCode: .requestNotSupported)
            return
        }
        guard request.characteristic.uuid == WhisperData.listenNameUuid else {
            logger.error("Got a write request for an unexpected characteristic: \(request)")
            manager.respondToWriteRequest(request: request, withCode: .unlikelyError)
            return
        }
        guard let value = request.value,
              let idAndName = String(data: value, encoding: .utf8) else {
            logger.error("Got an empty listener name value: \(request)")
            manager.respondToWriteRequest(request: request, withCode: .invalidAttributeValueLength)
            return
        }
        let parts = idAndName.split(separator: "|", maxSplits: 1)
        guard parts.count == 2 else {
            logger.error("Got an invalid format for listener name: \(idAndName)")
            manager.respondToWriteRequest(request: request, withCode: .unlikelyError)
            return
        }
        let candidate = Listener(deviceId: String(parts[0]), name: String(parts[1]))
        guard !droppedListeners.contains(where: { $0.deviceId == candidate.deviceId }) else {
            // dropped listeners cannot be re-aquired in this session
            logger.log("Refusing name write request from dropped listener \(candidate.deviceId)")
            manager.respondToWriteRequest(request: request, withCode: .insufficientAuthorization)
            return
        }
        candidates[request.central] = candidate
        logger.log("Received deviceId \(candidate.deviceId), name '\(candidate.name)' from candidate \(request.central)")
        manager.respondToWriteRequest(request: request, withCode: .success)
    }
    
    private func processReadyToUpdate(_ ignore: ()) {
        updateListeners()
    }
    
    // MARK: Internal helpers
    
    /// Update listeners on changes in live text
    private func updateListeners() {
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
        if advertisingInProgress {
            logger.log("Refresh advertising timer...")
            if let timer = adTimer {
                adTimer = nil
                timer.invalidate()
            }
        } else {
            logger.log("Advertising whisperer...")
        }
        manager.advertise(services: [WhisperData.whisperServiceUuid])
        advertisingInProgress = true
        let interval = max(listenerAdTime, whispererAdTime)
        adTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { timer in
            // run loop will invalidate the timer
            self.adTimer = nil
            self.stopAdvertising()
        }
        refreshStatusText()
    }
    
    private func stopAdvertising() {
        guard advertisingInProgress else {
            // nothing to do
            return
        }
        logger.log("Stop advertising whisperer")
        manager.stopAdvertising()
        listenAdvertisers.removeAll()
        advertisingInProgress = false
        if let timer = adTimer {
            // manual cancellation: invalidate the running timer
            adTimer = nil
            timer.invalidate()
        }
        refreshStatusText()
    }
    
    private func refreshStatusText() {
        guard !listeners.isEmpty else {
            if advertisingInProgress {
                statusText = "Looking for listeners..."
            } else {
                statusText = "No listeners yet, but you can type"
            }
            return
        }
        let maybeMore = advertisingInProgress ? ", looking for more..." : ""
        if listeners.count == 1 {
            statusText = "Whispering to 1 listener\(maybeMore)"
        } else {
            statusText = "Whispering to \(listeners.count) listeners\(maybeMore)"
        }
    }
    
    private func addListener(_ central: CBCentral, deviceId: String, name: String) {
        guard listeners[central] == nil else {
            // we've already connected this listener
            return
        }
        listeners[central] = Listener(deviceId: deviceId, name: name)
        logger.log("Added listener with deviceId \(deviceId), name \(name): \(central)")
        refreshStatusText()
    }
    
    private func removeListener(_ central: CBCentral) {
        guard let removed = listeners.removeValue(forKey: central) else {
            logger.error("Ignoring request to remove non-listener: \(central)")
            return
        }
        logger.log("Lost\(self.listeners.isEmpty ? " last" : "") listener \(removed.deviceId) (\(removed.name)): \(central)")
        refreshStatusText()
    }
}
