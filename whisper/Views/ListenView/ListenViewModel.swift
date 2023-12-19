// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import AVFAudio
import Combine
import CoreBluetooth
import UserNotifications

final class ListenViewModel: ObservableObject {
    typealias Remote = ComboFactory.Subscriber.Remote
    typealias Transport = ComboFactory.Subscriber

    @Published var statusText: String = ""
    @Published var liveText: String = ""
    @Published var connectionError: Bool = false
    @Published var conversationEnded: Bool = false
    @Published var connectionErrorDescription: String = "The connection to the whisperer was lost"
    @Published var showStatusDetail: Bool = false
    @Published var candidates: [Remote] = []
    @Published var whisperer: Remote?
    @Published var pastText: PastTextModel = .init(mode: .listen)
    
    private var transport: Transport
    private var manualWhisperer: Bool
    private var cancellables: Set<AnyCancellable> = []
    private var discoveryInProgress = false
    private var discoveryCountDown = 0
    private var discoveryTimer: Timer?
    private var resetInProgress = false
    private var isFirstConnect = true
    private var isInBackground = false
    private var soundEffect: AVAudioPlayer?
    private var notifySoundInBackground = false
    private static let synthesizer = AVSpeechSynthesizer()

    init(_ conversation: Conversation?) {
        logger.log("Initializing ListenView model")
        manualWhisperer = conversation != nil
        transport = ComboFactory.shared.subscriber(conversation)
        transport.addRemoteSubject
            .sink{ [weak self] in self?.addCandidate($0) }
            .store(in: &cancellables)
        transport.dropRemoteSubject
            .sink{ [weak self] in self?.dropCandidate($0) }
            .store(in: &cancellables)
        transport.contentSubject
            .sink{ [weak self] in self?.receiveChunk($0) }
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
        resetTextForConnection()
        if !manualWhisperer {
            awaitDiscovery()
        }
        refreshStatusText()
        transport.start(failureCallback: signalConnectionError)
    }
    
    func stop() {
        cancelDiscovery()
        transport.stop()
        statusText = "Stopped Listening"
    }
    
    func wentToBackground() {
        guard !isInBackground else {
            return
        }
        isInBackground = true
        transport.goToBackground()
    }
    
    func wentToForeground() {
        guard isInBackground else {
            return
        }
        isInBackground = false
        transport.goToForeground()
        // after going to background, assume not waiting any more
        logger.log("End initial wait for whisperers due to background transition")
        discoveryInProgress = false
        maybeSetWhisperer()
    }
    
    /// Set the passed candidate to be the whisperer
    func setWhisperer(_ to: Remote) {
        guard whisperer == nil else {
            logger.error("Ignoring attempt to set whisperer when we already have one")
            return
        }
        logger.log("Selecting whisperer \(to.id) with name \(to.name)")
        whisperer = to
        // tell the transport we're subscribing (removes all other candidates)
        transport.subscribe(remote: to)
        // update the view
        refreshStatusText()
        if isFirstConnect {
            isFirstConnect = false
            pastText.clearLines()
        }
        liveText = ""
        // get anything we missed from whisperer
        readLiveText()
    }
    
    // re-read the whispered text
    func readLiveText() {
        guard whisperer != nil else {
            return
        }
        guard !resetInProgress else {
            logger.log("Got reset during reset, ignoring it")
            return
        }
        logger.log("Requesting re-read of live text")
        resetInProgress = true
        let chunk = WhisperProtocol.ProtocolChunk.replayRequest(hint: WhisperProtocol.ReadType.live)
        transport.sendControl(remote: whisperer!, chunks: [chunk])
    }
    
    // MARK: Transport subscription handlers
    private func addCandidate(_ remote: Remote) {
        guard !candidates.contains(where: { $0 === remote }) else {
            logger.error("Ignoring add of unnecessary or duplicate remote \(remote.id)")
            return
        }
        candidates.append(remote)
        maybeSetWhisperer()
    }
    
    private func dropCandidate(_ remote: Remote) {
        guard let position = candidates.firstIndex(where: { $0 === remote }) else {
            logger.error("Ignoring dropped non-candidate \(remote.id)")
            return
        }
        let removed = candidates.remove(at: position)
        if removed === whisperer {
            logger.info("Dropped the whisperer \(removed.id)")
            whisperer = nil
            // we have lost the whisperer, stop listening
            resetTextForConnection()
            refreshStatusText()
            conversationEnded = true
        } else {
            logger.info("Dropped candidate \(removed.id) with name \(removed.name)")
        }
    }
    
    private func receiveChunk(_ pair: (remote: Remote, chunk: WhisperProtocol.ProtocolChunk)) {
        guard pair.remote === whisperer else {
            logger.error("Ignoring chunk received from non-whisperer \(pair.remote.id)")
            return
        }
        processChunk(pair.chunk)
    }
        
    // MARK: internal helpers
    private func resetTextForConnection() {
        if isFirstConnect {
            liveText = connectingLiveText
            pastText.setFromText(connectingPastText)
        } else {
            self.liveText = connectingLiveText
        }
    }
    
    private func signalConnectionError(_ reason: String) {
        Task { @MainActor in
            connectionError = true
            connectionErrorDescription = reason
        }
    }
    
    private func processChunk(_ chunk: WhisperProtocol.ProtocolChunk) {
        if chunk.isSound() {
            logger.log("Received request to play sound '\(chunk.text)'")
            playSound(chunk.text)
        } else if resetInProgress {
            if chunk.isFirstRead() {
                logger.log("Received reset acknowledgement from whisperer")
            } else if chunk.isDiff() {
                logger.log("Ignoring diff chunk because a read is in progress")
            } else if chunk.isCompleteLine() {
                logger.debug("Got past line \(self.pastText.pastText.count) in read")
                pastText.addLine(chunk.text)
            } else if chunk.isLastRead() {
                logger.log("Reset completes with \(chunk.text.count) live characters")
                liveText = chunk.text
                resetInProgress = false
            }
        } else {
            if !chunk.isDiff() {
                logger.log("Ignoring non-diff chunk because no read in progress")
            } else if chunk.offset == 0 {
//                logger.debug("Got diff: live text is '\(chunk.text)'")
                liveText = chunk.text
            } else if chunk.isCompleteLine() {
//                logger.log("Got diff: move live text to past text")
                if !isInBackground && PreferenceData.speakWhenListening {
                    speak(liveText)
                }
                pastText.addLine(liveText)
                liveText = ""
            } else if chunk.offset > liveText.count {
                // we must have missed a packet, read the full state to reset
                PreferenceData.droppedErrorCount += 1
                logger.log("Resetting live text after missed packet...")
                readLiveText()
            } else {
//                logger.debug("Got diff: live text[\(chunk.offset)...] updated to '\(chunk.text)'")
                liveText = WhisperProtocol.applyDiff(old: liveText, chunk: chunk)
            }
        }
    }
    
    private func playSound(_ name: String) {
        var name = name
        var path = Bundle.main.path(forResource: name, ofType: "caf")
        if path == nil {
            // try again with default sound
            name = PreferenceData.alertSound
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
    
    /// Wait for a while so discovery can find multiple listeners
    private func awaitDiscovery() {
        guard !isInBackground else {
            fatalError("Can't start the listener scan in the background")
        }
        logger.log("Start initial wait for whisperers")
        discoveryInProgress = true
        discoveryCountDown = Int(listenerWaitTime)
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(1), repeats: true) { timer in
            guard self.discoveryInProgress && self.discoveryCountDown > 0 else {
                logger.log("End initial wait for whisperers due to timeout")
                timer.invalidate()
                self.discoveryTimer = nil
                self.discoveryCountDown = 0
                self.discoveryInProgress = false
                self.maybeSetWhisperer()
                return
            }
            self.discoveryCountDown -= 1
            self.refreshStatusText()
        }
    }
    
    /// Cancel the wait for discovery (only happens on shutdown)
    private func cancelDiscovery() {
        guard let timer = discoveryTimer else {
            return
        }
        timer.invalidate()
        discoveryTimer = nil
        discoveryInProgress = false
        // don't maybe set whisperer, because we have cancelled discovery
    }
    
    /// We may have found an an eligible whisper candidate.
    /// If so, connect to it.  Update status in any case.
    private func maybeSetWhisperer() {
        guard !discoveryInProgress else {
            // we are still waiting for more candidates
            return
        }
        if whisperer == nil {
            if candidates.count == 1 {
                // only 1 whisperer after waiting for the scan
                setWhisperer(candidates[0])
            }
        }
        refreshStatusText()
    }
        
    private func refreshStatusText() {
        if let whisperer = whisperer {
            statusText = "Listening to \(whisperer.name)"
        } else if discoveryInProgress {
            let suffix = discoveryCountDown > 0 ? " \(discoveryCountDown)" : ""
            statusText = "Looking for whisperers…\(suffix)"
        } else {
            let count = candidates.count
            if count == 0 {
                statusText = "Waiting for a whisperer to appear…"
            } else {
                statusText = "Tap to select your desired whisperer…"
            }
        }
    }
}
