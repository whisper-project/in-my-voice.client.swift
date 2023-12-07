// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import AVFAudio
import Combine
import CoreBluetooth

final class WhisperViewModel: ObservableObject {
    typealias Remote = ComboFactory.Publisher.Remote
    typealias Transport = ComboFactory.Publisher
    
    @Published var statusText: String = ""
    @Published var connectionError = false
    @Published var connectionErrorDescription: String = ""
    @Published var remotes: [String:Remote] = [:]
    @Published var pastText: PastTextModel = .init(mode: .whisper)

    private var transport: Transport
    private var cancellables: Set<AnyCancellable> = []
    
    private var liveText: String = ""
    private static let synthesizer = AVSpeechSynthesizer()
    private var soundEffect: AVAudioPlayer?

    init(_ publisherUrl: TransportUrl) {
        logger.log("Initializing WhisperView model")
        self.transport = ComboFactory.shared.publisher(publisherUrl)
        self.transport.addRemoteSubject
            .sink { [weak self] in self?.addListener($0) }
            .store(in: &cancellables)
        self.transport.dropRemoteSubject
            .sink { [weak self] in self?.removeListener($0) }
            .store(in: &cancellables)
        self.transport.receivedChunkSubject
            .sink { [weak self] in self?.sendAllText($0) }
            .store(in: &cancellables)
    }
    
    deinit {
        logger.log("Destroying WhisperView model")
        cancellables.cancel()
    }
    
    // MARK: View entry points
    
    func start() {
        resetText()
        refreshStatusText()
        transport.start(failureCallback: signalConnectionError)
    }
    
    func stop() {
        transport.stop()
        resetText()
        refreshStatusText()
    }
    
    /// Receive an updated live text from the view.
    /// Returns the new live text the view should display.
    func updateLiveText(old: String, new: String) -> String {
        guard old != new else {
            return liveText
        }
        let chunks = WhisperProtocol.diffLines(old: old, new: new)
        for chunk in chunks {
            if chunk.isCompleteLine() {
                pastText.addLine(liveText)
                if PreferenceData.speakWhenWhispering {
                    speak(liveText)
                }
                liveText = ""
            } else {
                liveText = WhisperProtocol.applyDiff(old: liveText, chunk: chunk)
            }
        }
        transport.publish(chunks: chunks)
        return liveText
    }
    
    /// User has submitted the live text
    func submitLiveText() -> String {
        return self.updateLiveText(old: liveText, new: liveText + "\n")
    }
    
    /// Play the alert sound to all the listeners
    func playSound() {
        let soundName = PreferenceData.alertSound
        if PreferenceData.speakWhenWhispering {
            playSoundLocally(soundName)
        }
        let chunk = WhisperProtocol.ProtocolChunk.sound(soundName)
        transport.publish(chunks: [chunk])
    }
    
    /// Send the alert sound to a specific listener
    func playSound(_ remote: Remote) {
        guard remotes[remote.id] != nil else {
            logger.log("Ignoring alert request for non-remote: \(remote.id)")
            return
        }
        let soundName = PreferenceData.alertSound
        let chunk = WhisperProtocol.ProtocolChunk.sound(soundName)
        transport.send(remote: remote, chunks: [chunk])
    }
    
    /// Drop a listener from the authorized list
    func dropListener(_ remote: Remote) {
        guard let listener = remotes[remote.id] else {
            logger.log("Ignoring drop request for non-remote: \(remote.id)")
            return
        }
        logger.notice("Dropping remote \(listener.id) with name \(listener.name)")
        transport.drop(remote: remote)
    }
    
    func wentToBackground() {
        transport.goToBackground()
    }
    
    func wentToForeground() {
        transport.goToForeground()
    }
    
    // MARK: Internal helpers
    private func resetText() {
        self.pastText.clearLines()
        self.liveText = ""
    }
    
    private func signalConnectionError(_ reason: String) {
        Task { @MainActor in
            connectionError = true
            connectionErrorDescription = reason
        }
    }
    
    private func addListener(_ remote: Remote) {
        guard remotes[remote.id] == nil else {
            logger.warning("Notified of new remote \(remote.id) which is already known")
            return
        }
        logger.log("Notified of new remote \(remote.id) with name \(remote.name)")
        remotes[remote.id] = remote
        refreshStatusText()
    }
    
    private func removeListener(_ remote: Remote) {
        guard let removed = remotes.removeValue(forKey: remote.id) else {
            logger.warning("Notified of dropped remote \(remote.id) which is not known")
            return
        }
        logger.log("Lost\(self.remotes.isEmpty ? " last" : "") remote \(removed.id) with name \(removed.name)")
        refreshStatusText()
    }

    // send live text to a specific listener who requests it
    private func sendAllText(_ pair: (remote: Remote, chunk: WhisperProtocol.ProtocolChunk)) {
        guard let remote = remotes[pair.remote.id] else {
            logger.warning("Read requested by unknown remote \(pair.remote.id)")
            return
        }
        let chunks = [WhisperProtocol.ProtocolChunk.fromLiveText(text: liveText)]
        transport.send(remote: remote, chunks: chunks)
    }
    
    // speak a set of words
    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        Self.synthesizer.speak(utterance)
    }
    
    // play the alert sound locally
    private func playSoundLocally(_ name: String) {
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

    private func refreshStatusText() {
        guard !remotes.isEmpty else {
            statusText = "No listeners yet, but you can type"
            return
        }
        if remotes.count == 1 {
            statusText = "Whispering to \(remotes.first!.value.name)"
        } else {
            statusText = "Whispering to \(remotes.count) listeners"
        }
    }
}
