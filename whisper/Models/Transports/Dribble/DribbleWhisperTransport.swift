// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine

final class DribbleWhisperTransport: PublishTransport {
    // MARK: protocol properties and methods
    
    typealias Remote = DribbleListener
    typealias Layer = DribbleFactory
    
    var addRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var dropRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var receivedChunkSubject: PassthroughSubject<(remote: Remote, chunk: TextProtocol.ProtocolChunk), Never> = .init()
    
    func start(failureCallback: @escaping (String) -> Void) {
        logger.log("Starting Dribble whisper transport")
        startDiscovery()
    }
    
    func stop() {
        logger.log("Stopping Dribble whisper transport")
        stopDiscovery()
        for listener in listeners.values {
            drop(remote: listener)
        }
        saveChunks()
    }
    
    func goToBackground() {
        // can't do discovery in the background
        stopDiscovery()
    }
    
    func goToForeground() {
    }
    
    func send(remote: DribbleListener, chunks: [TextProtocol.ProtocolChunk]) {
        guard let listener = listeners[remote.id] else {
            fatalError("Targeting a remote that's not a listener: \(remote.id)")
        }
        logger.warning("Targeted chunk to \(listener.id) being sent as broadcast")
        publish(chunks: chunks)
    }
    
    func drop(remote: DribbleListener) {
        guard let removed = listeners.removeValue(forKey: remote.id) else {
            fatalError("Dropping a remote that's not a listener: \(remote.id)")
        }
        dropRemoteSubject.send(removed)
    }
    
    func publish(chunks: [TextProtocol.ProtocolChunk]) {
        var elapsedTime = lastSendTime == nil ? 0 : Date.now.timeIntervalSince(lastSendTime!)
        lastSendTime = Date.now
        for chunk in chunks {
            let chunkString = String(decoding: chunk.toData(), as: UTF8.self)
            self.chunks.append(TimedChunk(elapsed: UInt64(elapsedTime * 1000), chunk: chunkString))
            elapsedTime = 0
        }
    }
    
    // MARK: internal types, properties, and initialization
    final class DribbleListener: TransportRemote {
        let id: String
        var name: String
        
        init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }
    
    private var lastSendTime: Date?
    private struct TimedChunk: Encodable {
        var elapsed: UInt64    // elapsed time since last packet in milliseconds
        var chunk: String
    }
    private var chunks: [TimedChunk] = []
    private var listeners: [String: DribbleListener] = [:]
    private var discoveryTimer: Timer?
    
    init() {
    }
    
    // MARK: internal methods
    private func startDiscovery() {
        guard discoveryTimer == nil else {
            logger.error("Discovery already in progress, ignoring request to start it")
            return
        }
        guard listeners.count < 2 else {
            logger.error("All discovery already completed, ignoring request to start it")
            return
        }
        logger.log("Starting dribble listener discovery...")
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
            if self.listeners["Listener-1"] == nil {
                logger.log("Discover dribble listener Seku")
                let new = DribbleListener(id: "Listener-1", name: "Seku")
                self.listeners[new.id] = new
                self.addRemoteSubject.send(new)
            } else if self.listeners["Listener-2"] == nil {
                logger.log("Discover dribble listener Asha")
                let new = DribbleListener(id: "Listener-2", name: "Asha")
                self.listeners[new.id] = new
                self.addRemoteSubject.send(new)
            } else {
                logger.log("Dribble listener discovery complete")
                timer.invalidate()
                self.discoveryTimer = nil
            }
        }
    }
    
    private func stopDiscovery() {
        guard let timer = discoveryTimer else {
            logger.error("Dribble listener discovery already complete, ignoring request to stop it")
            return
        }
        logger.log("Stopping dribble listener discovery...")
        timer.invalidate()
        discoveryTimer = nil
    }

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
}
