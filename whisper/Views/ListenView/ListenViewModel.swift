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
let unknownWhispererName = "(not yet known)"

final class ListenViewModel: ObservableObject {
    @Published var statusText: String = ""
    @Published var liveText: String = ""
    @Published var wasDropped: Bool = false
    var pastText: PastTextViewModel = .init()
    
    private var manager = BluetoothManager.shared
    private var cancellables: Set<AnyCancellable> = []
    private var whisperer: CBPeripheral?
    private var whispererName: String = unknownWhispererName
    static private var droppedWhisperers: Set<String> = []
    private var listenNameCharacteristic: CBCharacteristic?
    private var whisperNameCharacteristic: CBCharacteristic?
    private var textCharacteristic: CBCharacteristic?
    private var rejectCharacteristic: CBCharacteristic?
    private var scanInProgress = false
    private var scanTimer: Timer?
    private var resetInProgress = false
    private var disconnectInProgress = false
    private var isInBackground = false
    private var soundEffect: AVAudioPlayer?
    private var notifySoundInBackground = false

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
    
    func start() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if error != nil {
                logger.error("Error asking the user to approve alerts: \(error!)")
            }
            self.notifySoundInBackground = granted
        }
        findWhisperer()
    }
    
    func stop() {
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
            manager.stopAdvertising()
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
            manager.advertise(services: [WhisperData.listenServiceUuid])
        }
    }
    
    private func readAllText() {
        guard whisperer != nil && textCharacteristic != nil else {
            return
        }
        guard !resetInProgress else {
            logger.log("Got reset during reset, ignoring it")
            return
        }
        resetInProgress = true
        whisperer!.readValue(for: textCharacteristic!)
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
    
    private func findWhisperer() {
        guard whisperer == nil else {
            logger.log("Tried to find a whisperer when we have one, ignoring request")
            return
        }
        statusText = "Looking for a whisperer to listen to…"
        liveText = connectingLiveText
        pastText.setFromText(connectingPastText)
        if let peripheral = manager.connectedPeripherals(forServices: [WhisperData.whisperServiceUuid]).first,
           !Self.droppedWhisperers.contains(peripheral.identifier.uuidString),
           let service = peripheral.services?.first {
            logger.log("Found connected whisperer \(peripheral), readying it...")
            whisperer = peripheral
            whispererReady(service)
        } else if !scanInProgress {
            scanInProgress = true
            logger.log("Advertising listener and scanning for whisperer...")
            manager.scan(forServices: [WhisperData.whisperServiceUuid], allow_repeats: true)
            if isInBackground {
                logger.error("Starting to find whisperer while in background, don't advertise")
            } else {
                manager.advertise(services: [WhisperData.listenServiceUuid])
            }
        }
    }
    
    private func stopFindWhisperer(connectComplete: Bool) {
        if scanInProgress {
            scanInProgress = false
            logger.log("Stop advertising listener and scanning for whisperer")
            manager.stopScan()
            manager.stopAdvertising()
        }
        if connectComplete {
            statusText = "Listening to \(whispererName)"
            liveText = ""
            pastText.clearLines()
        }
    }
    
    private func foundWhisperer(_ pair: (CBPeripheral, [String: Any])) {
        guard !Self.droppedWhisperers.contains(pair.0.identifier.uuidString) else {
            logger.log("Ignoring whisperer that previously dropped us: \(pair.0)")
            return
        }
        stopFindWhisperer(connectComplete: false)
        guard whisperer == nil else {
            logger.log("Already have a whisperer, won't connect to \(pair.0) with ad \(pair.1)")
            return
        }
        if let uuids = pair.1[CBAdvertisementDataServiceUUIDsKey] as? Array<CBUUID> {
            if uuids.contains(WhisperData.whisperServiceUuid) {
                logger.log("Connecting to whisperer \(pair.0) with ad \(pair.1)")
                whisperer = pair.0
                manager.connect(whisperer!)
                return
            }
        }
        logger.error("Notified of whisperer with incorrect ad data: \(pair.1)")
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
            logger.log("Connected to whisperer \(self.whisperer!) with service \(pair.1), readying...")
            whisperer!.discoverCharacteristics(
                [
                    WhisperData.listenNameUuid,
                    WhisperData.whisperNameUuid,
                    WhisperData.whisperTextUuid,
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
        logger.log("Readying whisperer \(self.whisperer!)...")
        let allCs = service.characteristics!
        if let listenNameC = allCs.first(where: { $0.uuid == WhisperData.listenNameUuid }) {
            listenNameCharacteristic = listenNameC
            let idAndName = "\(WhisperData.deviceId)|\(WhisperData.deviceName)"
            whisperer?.writeValue(Data(idAndName.utf8), for: listenNameCharacteristic!, type: .withResponse)
        } else {
            fatalError("Whisper service has no listenName characteristic: please upgrade the Whisperer's app")
        }
        if let whisperNameC = allCs.first(where: { $0.uuid == WhisperData.whisperNameUuid }) {
            whisperNameCharacteristic = whisperNameC
            whisperer?.readValue(for: whisperNameCharacteristic!)
        } else {
            fatalError("Whisper service has no name characteristic: report a bug!")
        }
        if let liveTextC = allCs.first(where: { $0.uuid == WhisperData.whisperTextUuid }) {
            textCharacteristic = liveTextC
        } else {
            fatalError("Whisper service has no live text characteristic: report a bug!")
        }
        if let disconnectC = allCs.first(where: { $0.uuid == WhisperData.whisperDisconnectUuid }) {
            rejectCharacteristic = disconnectC
        } else {
            fatalError("Whisper service has no disconnect characteristic: report a bug!")
        }
        stopFindWhisperer(connectComplete: false)
    }
    
    private func wroteValue(_ triple: (CBPeripheral, CBCharacteristic, Error?)) {
        guard triple.0 == whisperer else {
            logger.error("Received write result for unexpected whisperer: \(triple.0)")
            return
        }
        guard triple.1.uuid == WhisperData.listenNameUuid else {
            logger.error("Received write result for unexpected characteristic: \(triple.1)")
            return
        }
        if let error = triple.2 {
            analyzeError(error)
        } else {
            // we have successfully paired with this whisperer
            stopFindWhisperer(connectComplete: true)
            whisperer!.setNotifyValue(true, for: textCharacteristic!)
            whisperer!.setNotifyValue(true, for: rejectCharacteristic!)
            readAllText()
        }
    }
    
    private func subscribedValue(_ triple: (CBPeripheral, CBCharacteristic, Error?)) {
        guard triple.0 == whisperer else {
            logger.error("Received notification result for unexpected whisperer: \(triple.0)")
            return
        }
        guard triple.1.uuid == WhisperData.whisperTextUuid || triple.1.uuid == WhisperData.whisperDisconnectUuid else {
            logger.error("Received notification result for unexpected characteristic: \(triple.1)")
            return
        }
        if let error = triple.2 {
            analyzeError(error)
        }
    }
    
    private func readValue(_ triple: (CBPeripheral, CBCharacteristic, Error?)) {
        guard triple.0 == whisperer else {
            fatalError("Read a value from unexpected peripheral \(triple.0)")
        }
        guard triple.2 == nil else {
            analyzeError(triple.2!)
            return
        }
        let characteristic = triple.1
        if characteristic.uuid == rejectCharacteristic?.uuid {
            logger.log("Received reject from whisperer")
            Self.droppedWhisperers.insert(whisperer!.identifier.uuidString)
            disconnect()
            wasDropped = true
        } else if characteristic.uuid == whisperNameCharacteristic?.uuid {
            logger.log("Received name value from whisperer")
            if let nameData = characteristic.value {
                if nameData.isEmpty {
                    whispererName = "(anonymous)"
                } else {
                    whispererName = String(decoding: nameData, as: UTF8.self)
                }
                statusText = "Listening to \(whispererName)"
            }
        } else if characteristic.uuid == textCharacteristic?.uuid {
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
        guard peripheral == whisperer else {
            logger.log("List whisperer service from \(peripheral) while connected to \(String(describing: self.whisperer))")
            return
        }
        logger.log("Whisperer service was unpublished")
        textCharacteristic = nil
        rejectCharacteristic = nil
        disconnect()
        wasDropped = true
    }
    
    private func analyzeError(_ error: Error) {
        guard !disconnectInProgress else {
            // we expect errors when a disconnect is in progress
            return
        }
        if let err = error as? CBATTError {
            switch err.code {
            case .insufficientEncryption:
                // we didn't pair so we couldn't encrypt
                logger.log("Whisperer required pairing but it was refused.")
            case .insufficientAuthorization:
                logger.log("Whisperer has this listener on its deny list.")
                Self.droppedWhisperers.insert(whisperer!.identifier.uuidString)
            default:
                logger.error("Unexpected communication error: \(err)")
            }
        } else {
            logger.error("Unexpected error in Bluetooth subsystem: \(String(describing: error))")
        }
        disconnect()
        wasDropped = true
    }
    
    private func disconnect() {
        guard !disconnectInProgress else {
            return
        }
        disconnectInProgress = true
        stopFindWhisperer(connectComplete: false)
        whisperNameCharacteristic = nil
        if let liveTextC = textCharacteristic {
            whisperer?.setNotifyValue(false, for: liveTextC)
            textCharacteristic = nil
        }
        if let disconnectC = rejectCharacteristic {
            whisperer?.setNotifyValue(false, for: disconnectC)
            rejectCharacteristic = nil
        }
        if let whisperP = whisperer {
            logger.log("Disconnecting existing whisperer \(self.whisperer!)")
            manager.disconnect(whisperP)
            whisperer = nil
            whispererName = unknownWhispererName
            whisperNameCharacteristic = nil
        }
        disconnectInProgress = false
    }
}
