// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine

final class DribbleWhisperTransport: Transport {
    // MARK: protocol properties and methods
    
    typealias Remote = DribbleListener
    typealias Layer = DribbleLayer
    
    var layer: DribbleLayer = DribbleLayer.shared
    
    var addRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var dropRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var receivedChunkSubject: PassthroughSubject<(remote: Remote, chunk: TextProtocol.ProtocolChunk), Never> = .init()
    
    func start() {
        logger.log("Starting Dribble Transport")
        var listenerCount = 0
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
            listenerCount += 1
            if listenerCount == 1 {
                logger.log("Discover dribble listener Seku")
                let new = DribbleListener(id: "Listener-1", name: "Seku")
                self.listeners[new.id] = new
                self.addRemoteSubject.send(new)
            } else if listenerCount == 2 {
                let new = DribbleListener(id: "Listener-2", name: "Asha")
                self.listeners[new.id] = new
                self.addRemoteSubject.send(new)
            } else {
                timer.invalidate()
            }
        }
    }
    
    func stop() {
        logger.log("Stopping Dribble Transport")
        for listener in listeners.values {
            drop(remote: listener)
        }
        saveChunks()
    }
    
    func goToBackground() {
    }
    
    func goToForeground() {
    }
    
    func sendChunks(chunks: [TextProtocol.ProtocolChunk]) {
        // save the chunk regardless of whether there's a current listener
        for chunk in chunks {
            let elapsedTime = Date.now.timeIntervalSince(self.startTime)
            let chunkString = String(decoding: chunk.toData(), as: UTF8.self)
            self.chunks.append(TimedChunk(elapsed: elapsedTime, chunk: chunkString))
        }
    }
    
    func sendChunks(remote: DribbleListener, chunks: [TextProtocol.ProtocolChunk]) {
        guard let listener = listeners[remote.id] else {
            fatalError("Targeting a remote that's not a listener: \(remote.id)")
        }
        logger.warning("Targeted chunk to \(remote.id) being sent as broadcast")
        sendChunks(chunks: chunks)
    }
    
    func drop(remote: DribbleListener) {
        guard let removed = listeners.removeValue(forKey: remote.id) else {
            fatalError("Dropping a remote that's not a listener: \(remote.id)")
        }
        dropRemoteSubject.send(removed)
    }
    
    // MARK: internal types, properties, and methods
    
    final class DribbleListener: TransportRemote {
        let id: String
        var name: String
        
        init(id: String = "Dribble-1", name: String = "Jenny") {
            self.id = id
            self.name = name
        }
    }
    
    private var startTime: Date!
    private struct TimedChunk: Encodable {
        var elapsed: TimeInterval
        var chunk: String
    }
    private var chunks: [TimedChunk] = []
    private var listeners: [String: DribbleListener] = [:]
    
    private func saveChunks() {
        do {
            let folderURL = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            let fileURL = folderURL.appendingPathComponent("DribbleTimedChunks.json")
            let data = try JSONEncoder().encode(self.chunks)
            try data.write(to: fileURL)
        }
        catch(let err) {
            logger.error("Failed to write DribbleTimedChunks: \(err)")
        }
    }
    
    init() {
        self.startTime = Date()
    }
}
