// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine

final class ComboListenTransport: SubscribeTransport {
    // MARK: Protocol properties and methods
    typealias Remote = Whisperer
    
    var addRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var dropRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var receivedChunkSubject: PassthroughSubject<(remote: Remote, chunk: TextProtocol.ProtocolChunk), Never> = .init()
    
    func start(commFailure: @escaping () -> Void) {
        logger.info("Starting combo listen transport")
        if let auto = autoTransport {
            auto.start(commFailure: commFailure)
        } else {
            manualTransport!.start(commFailure: commFailure)
        }
    }
    
    func stop() {
        logger.info("Stopping combo listen transport")
        autoTransport?.stop()
        manualTransport?.stop()
    }
    
    func goToBackground() {
        autoTransport?.goToBackground()
        manualTransport?.goToBackground()
    }
    
    func goToForeground() {
        autoTransport?.goToForeground()
        manualTransport?.goToForeground()
    }
    
    func send(remote: Whisperer, chunks: [TextProtocol.ProtocolChunk]) {
        guard let remote = whisperers[remote.id] else {
            fatalError("Targeting a remote that's not a whisperer: \(remote.id)")
        }
        switch remote.owner {
        case .auto:
            autoTransport!.drop(remote: remote.inner as! AutoRemote)
        case .manual:
            manualTransport!.drop(remote: remote.inner as! ManualRemote)
        }
    }

    func drop(remote: Whisperer) {
        guard let remote = whisperers[remote.id] else {
            fatalError("Dropping a remote that's not a whisperer: \(remote.id)")
        }
        switch remote.owner {
        case .auto:
            autoTransport!.drop(remote: remote.inner as! AutoRemote)
        case .manual:
            manualTransport!.drop(remote: remote.inner as! ManualRemote)
        }
    }

    func subscribe(remote: Whisperer) {
        guard let remote = whisperers[remote.id] else {
            fatalError("Subscribing to a remote that's not a whisperer: \(remote.id)")
        }
        switch remote.owner {
        case .auto:
            logger.info("Subscribing to an AutoRemote")
            autoTransport!.subscribe(remote: remote.inner as! AutoRemote)
        case .manual:
            logger.info("Subscribing to a ManualRemote")
            manualTransport!.subscribe(remote: remote.inner as! ManualRemote)
        }
    }
    
    // MARK: Internal types, properties, and initialization
#if targetEnvironment(simulator)
    typealias AutoTransport = DribbleListenTransport
    typealias AutoRemote = DribbleListenTransport.Remote
#else
    typealias AutoTransport = BluetoothListenTransport
    typealias AutoRemote = BluetoothListenTransport.Remote
#endif
    typealias ManualTransport = TcpListenTransport
    typealias ManualRemote = TcpListenTransport.Remote
    
    enum Owner {
        case auto
        case manual
    }
    
    final class Whisperer: TransportRemote {
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
    
    private var autoTransport: AutoTransport?
    private var manualTransport: ManualTransport?
    private var whisperers: [String: Whisperer] = [:]
    private var cancellables: Set<AnyCancellable> = []
    
    init(_ publisherUrl: TransportUrl) {
        logger.log("Initializing combo listen transport")
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
        } else {
            let autoTransport = AutoTransport()
            self.autoTransport = autoTransport
            autoTransport.addRemoteSubject
                .sink { [weak self] in self?.addListener(.auto, remote: $0) }
                .store(in: &cancellables)
            autoTransport.dropRemoteSubject
                .sink { [weak self] in self?.removeListener(.auto, remote: $0) }
                .store(in: &cancellables)
            autoTransport.receivedChunkSubject
                .sink { [weak self] in self?.receiveChunk($0) }
                .store(in: &cancellables)
        }
    }
    
    deinit {
        logger.log("Destroying combo listen transport")
        cancellables.cancel()
    }
    
    //MARK: internal methods
    private func addListener(_ owner: Owner, remote: any TransportRemote) {
        guard whisperers[remote.id] == nil else {
            logger.error("Ignoring add of existing remote \(remote.id) with name \(remote.name)")
            return
        }
        let whisperer = Whisperer(owner: owner, inner: remote)
        whisperers[remote.id] = whisperer
        addRemoteSubject.send(whisperer)
    }
    
    private func removeListener(_ owner: Owner, remote: any TransportRemote) {
        guard let removed = whisperers.removeValue(forKey: remote.id) else {
            logger.error("Ignoring drop of unknown remote \(remote.id) with name \(remote.name)")
            return
        }
        dropRemoteSubject.send(removed)
    }
    
    private func receiveChunk(_ pair: (remote: any TransportRemote, chunk: TextProtocol.ProtocolChunk)) {
        guard let whisperer = whisperers[pair.remote.id] else {
            logger.error("Ignoring chunk from unknown remote \(pair.remote.id) with name \(pair.remote.name)")
            return
        }
        receivedChunkSubject.send((remote: whisperer, chunk: pair.chunk))
    }
}
