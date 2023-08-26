// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine

final class DribbleListenTransport: SubscribeTransport {
    // MARK: Protocol properties and methods
    
    typealias Remote = Whisperer
    
    var addRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var dropRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var receivedChunkSubject: PassthroughSubject<(remote: Remote, chunk: TextProtocol.ProtocolChunk), Never> = .init()
    
    func start(commFailure: @escaping () -> Void) {
        logger.info("Starting Dribble listen transport...")
        startDiscovery()
    }
    
    func stop() {
        logger.info("Stopping Dribble listen transport")
        stopDiscovery()
        // there can only be one whisperer to drop
        if let whisperer = whisperers.first {
            drop(remote: whisperer)
        }
    }
    
    func goToBackground() {
        // can't do discovery in the background
        stopDiscovery()
    }
    
    func goToForeground() {
    }
    
    func send(remote: Remote, chunks: [TextProtocol.ProtocolChunk]) {
        guard remote === whisperers.first else {
            fatalError("Sending chunks to an unknown remote: \(remote.id)")
        }
        guard chunks.count == 1, let chunk = chunks.first, chunk.isReplayRequest() else {
            logger.error("Ignoring a chunk other than a request for replay")
            return
        }
        // The listener has requested a replay, so acknowledge, give an empty replay,
        // and then send the dribbled chunks as live text.
        let ack = TextProtocol.ProtocolChunk.acknowledgeRead(hint: "all")
        receivedChunkSubject.send((remote: remote, chunk: ack))
        let done = TextProtocol.ProtocolChunk.fromLiveText(text: "")
        receivedChunkSubject.send((remote: remote, chunk: done))
        sendChunks()
    }
    
    func drop(remote: Remote) {
        guard remote === whisperers.first else {
            fatalError("Dropping an unknown remote: \(remote.id)")
        }
        stopChunks()
        whisperers.removeFirst()
        dropRemoteSubject.send(remote)
    }
    
    func subscribe(remote: Remote) {
        guard remote === whisperers.first else {
            fatalError("Subscribing to an unknown remote: \(remote.id)")
        }
        // no need to look for other candidates
        stopDiscovery()
        // there aren't any other candidates to drop
    }
    
    // MARK: Internal types, properties, and initialization
    final class Whisperer: TransportRemote {
        var id: String
        var name: String
        
        fileprivate init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }
    
    private struct TimedChunk: Decodable {
        var elapsed: UInt64    // elapsed time since last packet in milliseconds
        var chunk: String
    }
    private var chunks: [TimedChunk] = []
    private var whisperers: [Remote] = []
    private var discoveryTimer: Timer?
    private var sendTask: Task<Void, Never>?

    init() {
        self.chunks = readChunks()
    }
    
    //MARK: internal methods
    private func startDiscovery() {
        guard whisperers.isEmpty, discoveryTimer == nil else {
            logger.log("Ignoring discovery request because discovery in progress or complete.")
            return
        }
        logger.log("Starting dribble whisper discovery...")
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
            if self.whisperers.isEmpty {
                let whisperer = Remote(id: "Dribbler-1", name: "Seku")
                self.whisperers.append(whisperer)
                self.addRemoteSubject.send(whisperer)
            }
            self.discoveryTimer = nil
        }
    }
    
    private func stopDiscovery() {
        guard let timer = discoveryTimer else {
            logger.log("Ignoring discovery cancellation because discovery already complete")
            return
        }
        logger.log("Stopping Dribble whisper discovery")
        timer.invalidate()
        discoveryTimer = nil
    }
    
    private func readChunks() -> [TimedChunk] {
        do {
            let folderURL = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            let url = folderURL.appendingPathComponent("DribbleTimedChunks.json")
            if let data = try? Data(contentsOf: url) {
                return try JSONDecoder().decode([TimedChunk].self, from: data)
            }
            guard let url = Bundle.main.url(forResource: "DribbleTimedChunks", withExtension: "json") else {
                logger.error("Missing DribbleTimedChunks.json from bundle")
                return []
            }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([TimedChunk].self, from: data)
        }
        catch(let err) {
            logger.error("Failed to read DribbleTimedChunks: \(err)")
            return []
        }
    }
    
    private func sendChunks() {
        guard sendTask == nil else {
            fatalError("Received request to send chunks while they are already being sent")
        }
        logger.log("Starting dribbling...")
        sendTask = Task {
            for chunk in self.chunks {
                if (Task.isCancelled) {
                    return
                }
                if chunk.elapsed > 0 {
                    try? await Task.sleep(nanoseconds: (chunk.elapsed - 1) * 1_000_000)
                }
                if (Task.isCancelled) {
                    return
                }
                if let remote = self.whisperers.first {
                    if let chunk = TextProtocol.ProtocolChunk.fromData(Data(chunk.chunk.utf8)) {
                        DispatchQueue.main.async {
                            self.receivedChunkSubject.send((remote: remote, chunk: chunk))
                        }
                    } else {
                        logger.error("Ignored illegal chunk: \(chunk.chunk)")
                    }
                } else {
                    return
                }
            }
        }
    }
    
    private func stopChunks() {
        if let task = sendTask {
            logger.log("Stopping dribbling...")
            sendTask = nil
            task.cancel()
        }
    }
}
