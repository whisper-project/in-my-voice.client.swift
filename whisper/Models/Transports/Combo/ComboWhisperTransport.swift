// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine

final class ComboWhisperTransport: PublishTransport {
    // MARK: protocol properties and methods
    typealias Remote = Listener
    
    var addRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var dropRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var receivedChunkSubject: PassthroughSubject<(remote: Remote, chunk: TextProtocol.ProtocolChunk), Never> = .init()
    
    func start(commFailure: @escaping () -> Void) {
        logger.log("Starting combo whisper transport")
        autoTransport.start(commFailure: commFailure)
        if let manual = manualTransport {
            manual.start(commFailure: commFailure)
        }
    }
    
    func stop() {
        logger.log("Stopping combo whisper transport")
        autoTransport.stop()
        manualTransport?.stop()
    }
    
    func goToBackground() {
        autoTransport.goToBackground()
        manualTransport?.goToBackground()
    }
    
    func goToForeground() {
        autoTransport.goToForeground()
        manualTransport?.goToForeground()
    }
    
    func send(remote: Listener, chunks: [TextProtocol.ProtocolChunk]) {
        guard let listener = listeners[remote.id] else {
            fatalError("Targeting a remote that's not a listener: \(remote.id)")
        }
        switch remote.owner {
        case .auto:
            autoTransport.drop(remote: listener.inner as! AutoRemote)
        case .manual:
            manualTransport?.drop(remote: listener.inner as! ManualRemote)
        }
    }
    
    func drop(remote: Listener) {
        guard let listener = listeners[remote.id] else {
            fatalError("Dropping a remote that's not a listener: \(remote.id)")
        }
        switch remote.owner {
        case .auto:
            autoTransport.drop(remote: listener.inner as! AutoRemote)
        case .manual:
            manualTransport?.drop(remote: listener.inner as! ManualRemote)
        }
    }
    
    func publish(chunks: [TextProtocol.ProtocolChunk]) {
        autoTransport.publish(chunks: chunks)
        manualTransport?.publish(chunks: chunks)
    }
    
    // MARK: internal types, properties, and initialization
#if targetEnvironment(simulator)
    typealias AutoTransport = DribbleWhisperTransport
    typealias AutoRemote = DribbleWhisperTransport.Remote
#else
    typealias AutoTransport = BluetoothWhisperTransport
    typealias AutoRemote = BluetoothWhisperTransport.Remote
#endif
    typealias ManualTransport = TcpWhisperTransport
    typealias ManualRemote = TcpWhisperTransport.Remote

    enum Owner {
        case auto
        case manual
    }
    
    final class Listener: TransportRemote {
        let id: String
        var name: String
        
        fileprivate var owner: Owner
        fileprivate var inner: (any TransportRemote)
        
        init(owner: Owner, inner: any TransportRemote) {
            self.owner = owner
            self.inner = inner
            self.id = inner.id
            self.name = inner.name
        }
    }
    
    private var autoTransport: AutoTransport
    private var manualTransport: TcpWhisperTransport?
    private var listeners: [String: Listener] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init(_ publisherUrl: TransportUrl) {
        logger.log("Initializing combo whisper transport")
        self.autoTransport = AutoTransport()
        self.autoTransport.addRemoteSubject
            .sink { [weak self] in self?.addListener(.auto, remote: $0) }
            .store(in: &cancellables)
        self.autoTransport.dropRemoteSubject
            .sink { [weak self] in self?.removeListener(.auto, remote: $0) }
            .store(in: &cancellables)
        self.autoTransport.receivedChunkSubject
            .sink { [weak self] in self?.receiveChunk($0) }
            .store(in: &cancellables)
        if let url = publisherUrl {
            let manualTransport = ManualTransport(url)
            self.manualTransport = manualTransport
            manualTransport.addRemoteSubject
                .sink { [weak self] in self?.addListener(.manual, remote: $0) }
                .store(in: &cancellables)
            manualTransport.dropRemoteSubject
                .sink { [weak self] in self?.removeListener(.manual, remote: $0) }
                .store(in: &cancellables)
            manualTransport.receivedChunkSubject
                .sink { [weak self] in self?.receiveChunk($0) }
                .store(in: &cancellables)
        }
    }
    
    deinit {
        logger.log("Destroying combo whisper transport")
        cancellables.cancel()
    }
    
    //MARK: internal methods
    private func addListener(_ owner: Owner, remote: any TransportRemote) {
        guard listeners[remote.id] == nil else {
            logger.error("Ignoring add of existing remote \(remote.id) with name \(remote.name)")
            return
        }
        let listener = Listener(owner: owner, inner: remote)
        listeners[remote.id] = listener
        addRemoteSubject.send(listener)
    }
    
    private func removeListener(_ owner: Owner, remote: any TransportRemote) {
        guard let removed = listeners.removeValue(forKey: remote.id) else {
            logger.error("Ignoring drop of unknown remote \(remote.id) with name \(remote.name)")
            return
        }
        dropRemoteSubject.send(removed)
    }
    
    private func receiveChunk(_ pair: (remote: any TransportRemote, chunk: TextProtocol.ProtocolChunk)) {
        guard let listener = listeners[pair.remote.id] else {
            logger.error("Ignoring chunk from unknown remote \(pair.remote.id) with name \(pair.remote.name)")
            return
        }
        receivedChunkSubject.send((remote: listener, chunk: pair.chunk))
    }
}
