// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import AVFAudio
import Combine
import CoreBluetooth
import UserNotifications

let connectingLiveText = "This is where the line being typed by the whisperer will appear in real time... "
let connectingPastText = """
    This is where lines will move after the whisperer hits return.
    The most recent line will be on the bottom.
    """

final class ListenViewModel: ObservableObject {
    class Candidate {
        var peripheral: CBPeripheral
        var deviceId: String
        var name: String = "(not yet known)"
        var isPrimary: Bool = false
        var isPaired: Bool = false
        var listenNameCharacteristic: CBCharacteristic?
        var whisperNameCharacteristic: CBCharacteristic?
        var textCharacteristic: CBCharacteristic?
        var rejectCharacteristic: CBCharacteristic?
        
        init(peripheral: CBPeripheral, deviceId: String) {
            self.peripheral = peripheral
            self.deviceId = deviceId
        }
        
        func setPrimary(isPrimary: Bool) {
            guard self.isPaired else {
                if isPrimary {
                    fatalError("Can't make unpaired candidate primary: \(self)")
                } else {
                    // nothing to do
                    return
                }
            }
            guard self.isPrimary != isPrimary else {
                // nothing to do
                return
            }
            self.isPrimary = isPrimary
            if let liveTextC = self.textCharacteristic {
                self.peripheral.setNotifyValue(isPrimary, for: liveTextC)
            }
            if let rejectC = self.rejectCharacteristic {
                self.peripheral.setNotifyValue(isPrimary, for: rejectC)
            }
        }
    }
    
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var bluetoothWaiting: Bool = true
    @Published var statusText: String = ""
    @Published var liveText: String = ""
    @Published var wasDropped: Bool = false
    @Published var timedOut: Bool = false
    var pastText: PastTextViewModel = .init()
    
    private var manager = BluetoothManager()
    private var cancellables: Set<AnyCancellable> = []
    private var candidates: [CBPeripheral: Candidate] = [:]
    private var whisperer: Candidate?
    static private var droppedWhisperers: Set<String> = []
    private var scanInProgress = false
    private weak var scanTimer: Timer?
    private var resetInProgress = false
    private var disconnectInProgress = false
    private var isInBackground = false
    private var soundEffect: AVAudioPlayer?
    private var notifySoundInBackground = false
    
    init() {
        manager.stateSubject
            .sink(receiveValue: setState)
            .store(in: &cancellables)
        manager.peripheralSubject
            .sink{ [weak self] in self?.discoveredWhisperer($0) }
            .store(in: &cancellables)
        manager.servicesSubject
            .sink{ [weak self] in self?.connectedWhisperer($0) }
            .store(in: &cancellables)
        manager.characteristicsSubject
            .sink{ [weak self] in self?.pairWithWhisperer($0) }
            .store(in: &cancellables)
        manager.receivedValueSubject
            .sink{ [weak self] in self?.readValue($0) }
            .store(in: &cancellables)
        manager.writeResultSubject
            .sink{ [weak self] in self?.confirmPairing($0) }
            .store(in: &cancellables)
        manager.notifyResultSubject
            .sink{ [weak self] in self?.subscribedValue($0) }
            .store(in: &cancellables)
        manager.disconnectedSubject
            .sink{ [weak self] in self?.wasDisconnected($0) }
            .store(in: &cancellables)
    }
    
    deinit {
        cancellables.cancel()
    }
    
    func start() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if error != nil {
                logger.error("Error asking the user to approve alerts: \(error!)")
            }
            self.notifySoundInBackground = granted
        }
    }
    
    func stop() {
        logger.log("Stop scanning for whisperers")
        manager.stopScan()
        if scanInProgress {
            scanInProgress = false
            logger.log("Stop advertising this listener")
            stopAdvertising()
        }
        // disconnect from already-found candidates
        disconnect()
        statusText = "Stopped Listening"
    }
    
    func wentToBackground() {
        guard !isInBackground else {
            return
        }
        isInBackground = true
        // now that we are doing background processing,
        // we need to stop advertising when we go to
        // the background, so as to save battery.
        if scanInProgress {
            stopAdvertising()
        }
    }
    
    func wentToForeground() {
        guard isInBackground else {
            return
        }
        isInBackground = false
        // if we are looking for a listener, resume
        // advertising now that we are  in the foreground.
        if scanInProgress {
            startAdvertising()
        }
    }
    
    func eligibleCandidates() -> [Candidate] {
        return candidates.values.filter{ $0.isPaired }
    }
    
    func switchPrimary(to: CBPeripheral) {
        guard var new = candidates[to], new.isPaired else {
            logger.error("Can't switch primary to non-candidate \(to)")
            return
        }
        switchPrimary(&new)
    }
    
    private func switchPrimary(_ new: inout Candidate) {
        if let old = whisperer {
            old.setPrimary(isPrimary: false)
            whisperer = nil
        }
        new.setPrimary(isPrimary: true)
        whisperer = new
        foundWhisperer()
        readAllText()
    }
    
    private func readAllText() {
        guard whisperer != nil else {
            return
        }
        guard !resetInProgress else {
            logger.log("Got reset during reset, ignoring it")
            return
        }
        resetInProgress = true
        whisperer!.peripheral.readValue(for: whisperer!.textCharacteristic!)
    }
    
    private func playSound(_ name: String) {
        var name = name
        var path = Bundle.main.path(forResource: name, ofType: "caf")
        if path == nil {
            // try again with default sound
            name = WhisperData.alertSound()
            path = Bundle.main.path(forResource: name, ofType: "caf")
        }
        guard path != nil else {
            logger.error("Couldn't find sound file for '\(name)'")
            return
        }
        guard !isInBackground else {
            notifySound(name)
            return
        }
        let url = URL(fileURLWithPath: path!)
        soundEffect = try? AVAudioPlayer(contentsOf: url)
        if let player = soundEffect {
            if !player.play() {
                logger.error("Couldn't play sound '\(name)'")
            }
        } else {
            logger.error("Couldn't create player for sound '\(name)'")
        }
    }
    
    private func notifySound(_ name: String) {
        guard notifySoundInBackground else {
            logger.error("Received background request to play sound '\(name)' but don't have permission.")
            return
        }
        let soundName = UNNotificationSoundName(name + ".caf")
        let sound = UNNotificationSound(named: soundName)
        let content = UNMutableNotificationContent()
        content.title = "Whisper"
        content.body = "The whisperer wants your attention!"
        content.sound = sound
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.25, repeats: false)
        let uuid = UUID().uuidString
        let request = UNNotificationRequest(identifier: uuid, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.add(request) { error in if error != nil { logger.error("Couldn't notify: \(error!)") } }
    }
    
    /// Start the process of looking for a listener.  This resets the status line, live, and past text and starts advertising.
    /// This is only done when we don't have any eligible candidate whisperers.
    private func findWhisperer() {
        guard whisperer == nil else {
            logger.error("Advertising for a whisperer when we have one, ignoring request")
            return
        }
        setStatusText()
        liveText = connectingLiveText
        pastText.setFromText(connectingPastText)
        if !scanInProgress {
            scanInProgress = true
            logger.log("Advertising listener...")
            if isInBackground {
                logger.error("Starting to find whisperer while in background, don't advertise")
            } else {
                startAdvertising()
            }
        }
    }
    
    /// Complete the process of looking for a listener.  This resets the status line, live and past text and stops any advertising.
    /// This is only done when we have paired with and are connecting to a candidate whisperer.
    private func foundWhisperer() {
        guard whisperer != nil else {
            logger.error("Stop advertising for a whisperer when we don't have one, ignoring the request")
            return
        }
        if scanInProgress {
            scanInProgress = false
            logger.log("Stop advertising listener")
            stopAdvertising()
        }
        setStatusText(name: whisperer!.name)
        liveText = ""
        pastText.clearLines()
    }
    
    private func setStatusText(name: String? = nil) {
        if bluetoothWaiting {
            if bluetoothState == .unauthorized {
                statusText = "Tap here to enable Bluetooth…"
            } else {
                statusText = "Waiting for Bluetooth to be ready…"
            }
        } else if let name = name {
            statusText = "Listening to \(name)"
            let eligible = eligibleCandidates().count - 1   // the whisperer is eligible
            if eligible > 0 {
                statusText += " (\(eligible) other\(eligible > 1 ? "s" : "") available)"
            }
        } else {
            statusText = "Advertising for a whisperer to listen to…"
        }
    }
    
    private func startAdvertising() {
        guard scanTimer == nil else {
            fatalError("Started advertising while already advertising: report a bug!")
        }
        func firstTimer(_: Timer) {
            self.scanTimer = nil
            if self.candidates.count == 0 {
                logger.log("Advertising timed out before we heard from any whisperers.")
                self.timedOut = true
            } else {
                logger.log("Advertising ended before we have completed pairing, but we have candidates.")
                self.scanTimer = Timer.scheduledTimer(withTimeInterval: pairingMaxTime, repeats: false, block: secondTimer)
            }
            manager.stopAdvertising()
        }
        func secondTimer(_: Timer) {
            self.scanTimer = nil
            if scanInProgress {
                logger.log("We couldn't successfully pair any candidates in time.")
                self.timedOut = true
            }
        }
        scanTimer = Timer.scheduledTimer(withTimeInterval: advertisingMaxTime, repeats: false, block: firstTimer)
        manager.advertise(services: [WhisperData.listenServiceUuid])
    }
    
    private func stopAdvertising() {
        manager.stopAdvertising()
        if let timer = scanTimer {
            // manual cancellation: invalidate the running timer
            scanTimer = nil
            timer.invalidate()
        }
    }
    
    /// Called when we see an ad from a potential whisperer
    private func discoveredWhisperer(_ pair: (CBPeripheral, [String: Any])) {
        if let uuids = pair.1[CBAdvertisementDataServiceUUIDsKey] as? Array<CBUUID> {
            if uuids.contains(WhisperData.whisperServiceUuid) {
                guard let adName = pair.1[CBAdvertisementDataLocalNameKey],
                      let deviceId = adName as? String else {
                    logger.error("Ignoring advertisement with no listener id")
                    return
                }
                guard candidates[pair.0] == nil else {
                    logger.debug("Ignoring repeat ad from candidate \(deviceId)")
                    return
                }
                logger.log("Connecting to candidate \(pair.0) with id \(deviceId)")
                candidates[pair.0] = Candidate(peripheral: pair.0, deviceId: deviceId)
                manager.connect(pair.0)
                return
            }
        }
        logger.error("Notified of whisperer \(pair.0) with incorrect ad data: \(pair.1)")
    }
    
    /// Called when we get a connection established to a potential whisperer
    private func connectedWhisperer(_ pair: (CBPeripheral, [CBService])) {
        guard let candidate = candidates[pair.0] else {
            fatalError("Connected to whisperer \(pair.0) but didn't request a connection")
        }
        if let whisperSvc = pair.1.first(where: {svc in svc.uuid == WhisperData.whisperServiceUuid}) {
            logger.log("Connected to whisperer \(candidate.deviceId), readying...")
            candidate.peripheral.discoverCharacteristics(
                [
                    WhisperData.listenNameUuid,
                    WhisperData.whisperNameUuid,
                    WhisperData.textUuid,
                    WhisperData.disconnectUuid,
                ],
                for: whisperSvc
            )
        } else {
            fatalError("Connected to advertised whisperer \(whisperer!) but it has no whisper service")
        }
    }
    
    /// Called when we have discovered the whisper service on a potential whisperer
    private func pairWithWhisperer(_ pair: (CBPeripheral, CBService)) {
        let (peripheral, service) = pair
        guard let candidate = candidates[peripheral] else {
            fatalError("Connected to a whisper service that's not a candidate: report a bug!")
        }
        guard service.characteristics != nil else {
            fatalError("Conected to a whisper service with no characteristics: report a bug!")
        }
        logger.log("Trying to pair with connected whisper service on: \(candidate.deviceId)...")
        let allCs = service.characteristics!
        if let listenNameC = allCs.first(where: { $0.uuid == WhisperData.listenNameUuid }) {
            candidate.listenNameCharacteristic = listenNameC
        } else {
            fatalError("Whisper service has no listenName characteristic: please upgrade the Whisperer's app")
        }
        if let whisperNameC = allCs.first(where: { $0.uuid == WhisperData.whisperNameUuid }) {
            candidate.whisperNameCharacteristic = whisperNameC
        } else {
            fatalError("Whisper service has no name characteristic: report a bug!")
        }
        if let liveTextC = allCs.first(where: { $0.uuid == WhisperData.textUuid }) {
            candidate.textCharacteristic = liveTextC
        } else {
            fatalError("Whisper service has no live text characteristic: report a bug!")
        }
        if let disconnectC = allCs.first(where: { $0.uuid == WhisperData.disconnectUuid }) {
            candidate.rejectCharacteristic = disconnectC
        } else {
            fatalError("Whisper service has no disconnect characteristic: report a bug!")
        }
        let idAndName = "\(WhisperData.deviceId)|\(WhisperData.deviceName)"
        peripheral.writeValue(Data(idAndName.utf8), for: candidate.listenNameCharacteristic!, type: .withResponse)
        peripheral.readValue(for: candidate.whisperNameCharacteristic!)
    }
    
    /// Get a confirmation or error from a pairing attempt with a candidate whisperer
    private func confirmPairing(_ triple: (CBPeripheral, CBCharacteristic, Error?)) {
        guard var candidate = candidates[triple.0] else {
            fatalError("Received write result for a non-candidate: \(triple.0)")
        }
        guard triple.1.uuid == WhisperData.listenNameUuid else {
            fatalError("Received write result for unexpected characteristic: \(triple.1)")
        }
        if let error = triple.2 {
            analyzeError(candidate: candidate, error: error)
        } else if whisperer == nil {
            // we have successfully paired for the first time
            candidate.isPaired = true
            switchPrimary(&candidate)
        } else {
            // we already have a whisperer, but now we have another paired candidate
            candidate.isPaired = true
        }
    }
    
    private func subscribedValue(_ triple: (CBPeripheral, CBCharacteristic, Error?)) {
        guard let candidate = candidates[triple.0] else {
            logger.error("Received notification result for unexpected whisperer: \(triple.0)")
            return
        }
        guard triple.1.uuid == WhisperData.textUuid || triple.1.uuid == WhisperData.disconnectUuid else {
            logger.error("Received notification result for unexpected characteristic: \(triple.1)")
            return
        }
        if let error = triple.2 {
            analyzeError(candidate: candidate, error: error)
        }
    }
    
    private func readValue(_ triple: (CBPeripheral, CBCharacteristic, Error?)) {
        guard let candidate = candidates[triple.0] else {
            logger.error("Read a value from an unexpected whisperer: \(triple.0)")
            return
        }
        guard triple.2 == nil else {
            analyzeError(candidate: candidate, error: triple.2!)
            return
        }
        let characteristic = triple.1
        if characteristic.uuid == candidate.rejectCharacteristic?.uuid {
            logger.log("Received reject from candidate")
            wasDisconnected(candidate.peripheral)
        } else if characteristic.uuid == candidate.whisperNameCharacteristic?.uuid {
            logger.log("Received name value from candidate")
            if let nameData = characteristic.value {
                if nameData.isEmpty {
                    candidate.name = candidate.deviceId
                } else {
                    candidate.name = String(decoding: nameData, as: UTF8.self)
                }
                if candidate.isPrimary {
                    setStatusText(name: candidate.name)
                }
            }
        } else if characteristic.uuid == candidate.textCharacteristic?.uuid {
            guard candidate.isPrimary else {
                logger.error("Ignoring text data from non-primary candidate: \(candidate.deviceId)")
                return
            }
            if let textData = characteristic.value,
               let chunk = TextProtocol.ProtocolChunk.fromData(textData) {
                if chunk.isSound() {
                    logger.log("Received request to play sound '\(chunk.text)'")
                    playSound(chunk.text)
                } else if resetInProgress {
                    if chunk.isFirstRead() {
                        logger.log("Received reset acknowledgement from whisperer, clearing past text")
                        pastText.clearLines()
                    } else if chunk.isDiff() {
                        logger.log("Ignoring diff chunk because a read is in progress")
                    } else if chunk.isCompleteLine() {
                        logger.debug("Got past line \(self.pastText.pastText.count) in read")
                        pastText.addLine(chunk.text)
                    } else if chunk.isLastRead() {
                        logger.log("Reset completes with \(self.pastText.pastText.count) past lines & \(chunk.text.count) live characters")
                        liveText = chunk.text
                        resetInProgress = false
                    }
                } else {
                    if !chunk.isDiff() {
                        logger.log("Ignoring non-diff chunk because no read in progress")
                    } else if chunk.offset == 0 {
                        logger.debug("Got diff: live text is '\(chunk.text)'")
                        liveText = chunk.text
                    } else if chunk.isCompleteLine() {
                        logger.log("Got diff: move live text to past text")
                        pastText.addLine(liveText)
                        liveText = ""
                    } else if chunk.offset > liveText.count {
                        // we must have missed a packet, read the full state to reset
                        logger.log("Resetting after missed packet...")
                        readAllText()
                    } else {
                        logger.debug("Got diff: live text[\(chunk.offset)...] updated to '\(chunk.text)'")
                        liveText = TextProtocol.applyDiff(old: liveText, chunk: chunk)
                    }
                }
            }
        } else {
            logger.log("Got a received value notification for an unexpected characteristic: \(characteristic)")
        }
    }
    
    private func wasDisconnected(_ peripheral: CBPeripheral) {
        guard let candidate = candidates[peripheral] else {
            logger.log("Lost whisperer service from non-candidate: \(peripheral)")
            return
        }
        logger.log("We were rejected from or service lost with candidate: \(candidate.deviceId)")
        guard !candidate.isPrimary else {
            // the connected whisperer has vanished
            disconnect()
            wasDropped = true
            return
        }
        candidates.removeValue(forKey: peripheral)
        if let whisperer = whisperer {
            setStatusText(name: whisperer.name)
        }
    }
    
    private func analyzeError(candidate: Candidate, error: Error) {
        guard !disconnectInProgress else {
            // we expect errors when a disconnect is in progress
            return
        }
        guard !candidate.isPrimary else {
            // the whisperer was disconnected
            disconnect()
            wasDropped = true
            return
        }
        if let err = error as? CBATTError {
            switch err.code {
            case .insufficientEncryption:
                // we didn't pair so we couldn't encrypt
                logger.log("Candidate requested pairing but it was refused.")
            case .insufficientAuthorization:
                logger.log("Candidate has this listener on its deny list.")
            default:
                logger.error("Unexpected communication error: \(err)")
            }
        } else {
            logger.error("Unexpected error in Bluetooth subsystem: \(String(describing: error))")
        }
    }
    
    private func disconnect() {
        guard !disconnectInProgress else {
            return
        }
        logger.log("Disconnecting all candidates!")
        disconnectInProgress = true
        whisperer = nil
        for candidate in candidates.values {
            if candidate.isPrimary {
                logger.log("Unsubscribing primary: \(candidate.deviceId)")
                candidate.setPrimary(isPrimary: false)
            }
            // warn the whisperer of the disconnect
            logger.log("Disconnecting candidate: \(candidate.deviceId)")
            if let dc = candidate.rejectCharacteristic {
                candidate.peripheral.writeValue(Data(), for: dc, type: .withoutResponse)
            }
        }
        for candidate in candidates.values {
            // actually disconnect
            manager.disconnect(candidate.peripheral)
        }
        candidates.removeAll()
        disconnectInProgress = false
    }
    
    private func startListening() {
        logger.log("Start scanning for whisperers...")
        manager.scan(forServices: [WhisperData.whisperServiceUuid], allow_repeats: true)
        // advertise this listener
        findWhisperer()
    }
    
    private func setState(_ new: CBManagerState) {
        if new != bluetoothState {
            logger.log("Bluetooth state changes to \(String(describing: new))")
            bluetoothState = new
        } else {
            logger.log("Bluetooth state remains \(String(describing: new))")
        }
        if bluetoothWaiting {
            if bluetoothState == .poweredOn {
                bluetoothWaiting = false
                startListening()
            }
        }
    }
}
