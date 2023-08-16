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
    class Whisperer {
        var peripheral: CBPeripheral
        var deviceId: String
        var name: String = ""
        var listenNameCharacteristic: CBCharacteristic?
        var whisperNameCharacteristic: CBCharacteristic?
        var textCharacteristic: CBCharacteristic?
        var rejectCharacteristic: CBCharacteristic?
        var sentName: Bool = false
        var haveName: Bool = false

        init(peripheral: CBPeripheral, deviceId: String) {
            self.peripheral = peripheral
            self.deviceId = deviceId
        }
        
        func canBeWhisperer() -> Bool {
            return self.sentName && self.haveName
        }
    }
    
    @Published var speaking: Bool = WhisperData.startSpeaking()
    @Published var statusText: String = ""
    @Published var liveText: String = ""
    @Published var wasDropped: Bool = false
    @Published var connectionError: Bool = false
    @Published var showStatusDetail: Bool = false
    @Published var candidates: [CBPeripheral: Whisperer] = [:]
    @Published var whisperer: Whisperer?
    var pastText: PastTextViewModel = .init()
    
    private var manager = BluetoothLayer.shared
    private var cancellables: Set<AnyCancellable> = []
    private var scanInProgress = false
    private var scanRefreshCount = 0
    private var resetInProgress = false
    private var disconnectInProgress = false
    private var isInBackground = false
    private var soundEffect: AVAudioPlayer?
    private var notifySoundInBackground = false
    private static let synthesizer = AVSpeechSynthesizer()

    init() {
        logger.log("Initializing ListenView model")
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
            .sink{ [weak self] in self?.wroteValue($0) }
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
    
    // MARK: View entry points
    
    func start() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if error != nil {
                logger.error("Error asking the user to approve alerts: \(error!)")
            }
            self.notifySoundInBackground = granted
        }
        startWhisperScan()
    }
    
    func stop() {
        manager.stopScan()
        stopAdvertising()
        // disconnect from current whisperer
        disconnect()
        statusText = "Stopped Listening"
    }
    
    func wentToBackground() {
        guard !isInBackground else {
            return
        }
        isInBackground = true
        // the timer to stop advertising won't run in the background
        stopAdvertising()
    }
    
    func wentToForeground() {
        guard isInBackground else {
            return
        }
        isInBackground = false
        // the timer to stop the scan wouldn't run in the background
        logger.log("End initial wait for whisperers due to background transition")
        scanInProgress = false
        maybeSetWhisperer()
    }
    
    func setWhisperer(to: CBPeripheral) {
        guard to != whisperer?.peripheral else {
            // nothing to do
            return
        }
        guard let new = candidates[to], new.canBeWhisperer() else {
            fatalError("Can't set whisperer to: \(to)")
        }
        setWhisperer(new)
        refreshStatusText()
    }
    
    func readAllText() {
        guard whisperer != nil else {
            return
        }
        guard !resetInProgress else {
            logger.log("Got reset during reset, ignoring it")
            return
        }
        logger.log("Requesting full re-read of text")
        resetInProgress = true
        whisperer!.peripheral.readValue(for: whisperer!.textCharacteristic!)
    }

    // MARK: Central event handlers
    
    /// Called when we see an ad from a potential whisperer
    private func discoveredWhisperer(_ pair: (CBPeripheral, [String: Any])) {
        guard whisperer == nil else {
            // ignore ads if we have a whisperer
            return
        }
        if let uuids = pair.1[CBAdvertisementDataServiceUUIDsKey] as? Array<CBUUID> {
            if uuids.contains(WhisperData.whisperServiceUuid) {
                guard let adName = pair.1[CBAdvertisementDataLocalNameKey],
                      let deviceId = adName as? String else {
                    logger.error("Ignoring advertisement with no device id")
                    return
                }
                guard candidates[pair.0] == nil else {
//                    logger.debug("Ignoring repeat ad from candidate \(deviceId)")
                    return
                }
                logger.log("Connecting to candidate \(deviceId): \(pair.0)")
                candidates[pair.0] = Whisperer(peripheral: pair.0, deviceId: deviceId)
                manager.connect(pair.0)
                return
            }
        }
    }
    
    /// Called when we get a connection established to a potential whisperer
    private func connectedWhisperer(_ pair: (CBPeripheral, [CBService])) {
        guard let candidate = candidates[pair.0] else {
            fatalError("Connected to candidate \(pair.0) but didn't request a connection")
        }
        if let whisperSvc = pair.1.first(where: {svc in svc.uuid == WhisperData.whisperServiceUuid}) {
            logger.log("Connected to candidate \(candidate.deviceId), readying...")
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
    
    /// Called when we have discovered characteristics for the whisper service on a candidate
    private func pairWithWhisperer(_ pair: (CBPeripheral, CBService)) {
        let (peripheral, service) = pair
        guard let candidate = candidates[peripheral] else {
            fatalError("Connected to a whisper service that's not a candidate")
        }
        guard service.characteristics != nil else {
            fatalError("Conected to a whisper service with no characteristics")
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
            fatalError("Whisper service has no name characteristic")
        }
        if let liveTextC = allCs.first(where: { $0.uuid == WhisperData.textUuid }) {
            candidate.textCharacteristic = liveTextC
        } else {
            fatalError("Whisper service has no live text characteristic")
        }
        if let disconnectC = allCs.first(where: { $0.uuid == WhisperData.disconnectUuid }) {
            candidate.rejectCharacteristic = disconnectC
        } else {
            fatalError("Whisper service has no disconnect characteristic")
        }
        let idAndName = "\(WhisperData.deviceId)|\(WhisperData.userName())"
        peripheral.writeValue(Data(idAndName.utf8), for: candidate.listenNameCharacteristic!, type: .withResponse)
        peripheral.readValue(for: candidate.whisperNameCharacteristic!)
    }
    
    /// Get a confirmation or error from an attempt to write our name to a candidate
    private func wroteValue(_ triple: (CBPeripheral, CBCharacteristic, Error?)) {
        guard let candidate = candidates[triple.0] else {
            fatalError("Received write result for a non-candidate: \(triple.0)")
        }
        guard triple.1.uuid == WhisperData.listenNameUuid else {
            fatalError("Received write result for unexpected characteristic: \(triple.1)")
        }
        if triple.2 != nil {
            logger.log("Pairing failed with candidate \(candidate.deviceId): \(triple.2)")
            candidates.removeValue(forKey: candidate.peripheral)
            manager.disconnect(candidate.peripheral)
        } else {
            logger.log("Successfully sent name to \(candidate.deviceId)")
            candidate.sentName = true
            maybeSetWhisperer()
        }
    }
    
    private func subscribedValue(_ triple: (CBPeripheral, CBCharacteristic, Error?)) {
        guard triple.0 == whisperer?.peripheral else {
            logger.error("Received subscription result for non-whisperer: \(triple.0)")
            return
        }
        guard triple.1.uuid == WhisperData.textUuid || triple.1.uuid == WhisperData.disconnectUuid else {
            logger.error("Received subscription result for unexpected characteristic: \(triple.1)")
            return
        }
        guard !disconnectInProgress else {
            // ignore errors during disconnect
            return
        }
        guard triple.2 != nil else {
            // no action needed on success
            return
        }
        logger.error("Failed to subscribe or unsubscribe the whisperer")
        wasDropped = true
    }
    
    private func readValue(_ triple: (CBPeripheral, CBCharacteristic, Error?)) {
        guard !disconnectInProgress else {
            return
        }
        if triple.0 == whisperer?.peripheral {
            if let error = triple.2 {
                logger.error("Got error on whisperer read: \(error)")
                connectionError = true
            } else if triple.1.uuid == whisperer!.rejectCharacteristic!.uuid {
                logger.log("Whisperer received reject from candidate")
                wasDropped = true
            } else if triple.1.uuid == whisperer!.textCharacteristic!.uuid {
                if let textData = triple.1.value,
                   let chunk = TextProtocol.ProtocolChunk.fromData(textData) {
                    processChunk(chunk)
                } else {
                    logger.error("Whisperer received non-chunk on text read, ignoring it")
                }
            } else {
                logger.error("Whisperer received value for an unexpected characteristic: \(triple.1)")
            }
        } else if let candidate = candidates[triple.0] {
            if let error = triple.2 {
                logger.error("Got error on candidate read: \(error)")
                candidates.removeValue(forKey: triple.0)
            } else if triple.1.uuid == candidate.rejectCharacteristic!.uuid {
                logger.log("Candidate \(candidate.deviceId) acknowledged drop request")
                manager.disconnect(triple.0)
            } else if triple.1 == candidate.whisperNameCharacteristic! {
                logger.log("Received name value from candidate \(candidate.deviceId)")
                if let nameData = triple.1.value, !nameData.isEmpty {
                    candidate.haveName = true
                    candidate.name = String(decoding: nameData, as: UTF8.self)
                    maybeSetWhisperer()
                } else {
                    logger.error("Received malformed name value from candidate \(candidate.deviceId), dropping it")
                    candidate.peripheral.readValue(for: candidate.rejectCharacteristic!)
                    candidates.removeValue(forKey: triple.0)
                }
            } else {
                logger.error("Candidate \(candidate.deviceId) read value for an unexpected characteristic: \(triple.1)")
            }
        } else {
            logger.error("Read a value from an unexpected source: \(triple.0)")
        }
    }
    
    private func wasDisconnected(_ peripheral: CBPeripheral) {
        if peripheral == whisperer?.peripheral {
            logger.log("Whisperer has stopped whispering")
            manager.disconnect(whisperer!.peripheral)
            whisperer = nil
            wasDropped = true
        } else if let candidate = candidates.removeValue(forKey: peripheral) {
            logger.log("Candidate \(candidate.deviceId) has stopped whispering")
            manager.disconnect(candidate.peripheral)
            // see if that resolves which whisperer to use
            maybeSetWhisperer()
        } else {
            logger.log("Ignoring disconnect from unknown whisperer: \(peripheral)")
        }
    }
    
    // MARK: internal helpers
    
    private func processChunk(_ chunk: TextProtocol.ProtocolChunk) {
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
                if !isInBackground && speaking {
                    speak(liveText)
                }
                pastText.addLine(liveText)
                liveText = ""
            } else if chunk.offset > liveText.count {
                // we must have missed a packet, read the full state to reset
                logger.log("Resetting after missed packet...")
                connectionError = true
            } else {
                logger.debug("Got diff: live text[\(chunk.offset)...] updated to '\(chunk.text)'")
                liveText = TextProtocol.applyDiff(old: liveText, chunk: chunk)
            }
        }
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
    
    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        Self.synthesizer.speak(utterance)
    }
    
    /// Start the scan for a listener.
    /// This starts the scan timer.  We won't select a whisperer until
    /// This resets the status line, live, and past text and starts advertising.
    private func startWhisperScan() {
        guard !isInBackground else {
            fatalError("Can't start the listener scan in the background")
        }
        logger.log("Start scanning for whisperers")
        manager.scan(forServices: [WhisperData.whisperServiceUuid], allow_repeats: true)
        logger.log("Start initial wait for whisperers")
        liveText = connectingLiveText
        pastText.setFromText(connectingPastText)
        scanInProgress = true
        scanRefreshCount = Int(listenerWaitTime)
        refreshStatusText()
        Timer.scheduledTimer(withTimeInterval: TimeInterval(1), repeats: true) { timer in
            guard self.scanInProgress && self.scanRefreshCount > 0 else {
                timer.invalidate()
                self.scanRefreshCount = 0
                return
            }
            self.scanRefreshCount -= 1
            self.refreshStatusText()
        }
        Timer.scheduledTimer(withTimeInterval: listenerWaitTime, repeats: false) { _ in
            logger.log("End initial wait for whisperers due to timeout")
            self.scanInProgress = false
            self.maybeSetWhisperer()
        }
        startAdvertising()
    }
    
    /// We may have found an an eligible whisper candidate.
    /// If so, connect to it.  Update status in any case.
    private func maybeSetWhisperer() {
        guard !scanInProgress else {
            // we are still waiting for more candidates
            return
        }
        if whisperer == nil {
            let eligible = candidates.values.filter({ $0.canBeWhisperer() })
            if eligible.count == 1 {
                // only 1 whisperer after waiting for the scan
                setWhisperer(eligible[0])
            }
        }
        refreshStatusText()
    }
    
    /// Set the passed candidate to be the whisperer
    private func setWhisperer(_ to: Whisperer) {
        guard to.canBeWhisperer() else {
            fatalError("Can't set whisperer to \(to.deviceId)")
        }
        logger.log("Selecting whisperer \(to.deviceId) (\(to.name))")
        // subscribe the whisperer
        whisperer = to
        to.peripheral.setNotifyValue(true, for: to.textCharacteristic!)
        to.peripheral.setNotifyValue(true, for: to.rejectCharacteristic!)
        readAllText()
        // drop the unused candidates
        for candidate in candidates.values {
            if candidate === to {
                continue
            }
            logger.log("Dropping unused candidate \(candidate.deviceId) (\(candidate.name))")
            candidate.peripheral.readValue(for: candidate.rejectCharacteristic!)
        }
        candidates.removeAll()
    }

    
    private func refreshStatusText() {
        if let whisperer = whisperer {
            statusText = "Listening to \(whisperer.name)"
        } else if scanInProgress {
            let suffix = scanRefreshCount > 0 ? " \(scanRefreshCount)" : ""
            statusText = "Looking for whisperers…\(suffix)"
        } else {
            let count = candidates.values.filter({ $0.canBeWhisperer() }).count
            if count > 1 {
                statusText = "Tap to select your desired whisperer…"
                showStatusDetail = true
            } else {
                statusText = "Waiting for a whisperer to appear…"
            }
        }
    }
    
    private func startAdvertising() {
        logger.log("Start advertising listener")
        Timer.scheduledTimer(withTimeInterval: listenerAdTime, repeats: false) { _ in
            self.stopAdvertising()
        }
        manager.advertise(services: [WhisperData.listenServiceUuid])
    }
    
    private func stopAdvertising() {
        logger.log("Stop advertising listener")
        manager.stopAdvertising()
    }
    
    private func analyzeError(candidate: Whisperer, error: Error) {
        guard !disconnectInProgress else {
            // we expect errors when a disconnect is in progress
            return
        }
        guard whisperer !== candidate else {
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
        disconnectInProgress = true
        if let whisperer = whisperer {
            logger.log("Disconnecting the whisperer")
            whisperer.peripheral.setNotifyValue(false, for: whisperer.textCharacteristic!)
            manager.disconnect(whisperer.peripheral)
        }
        disconnectInProgress = false
    }
}
