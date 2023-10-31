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
    
    func start(failureCallback: @escaping (String) -> Void) {
        logger.log("Starting combo whisper transport")
        self.failureCallback = failureCallback
        initializeTransports()
        if let auto = autoTransport {
            auto.start(failureCallback: failureCallback)
        }
        if let manual = manualTransport {
            manual.start(failureCallback: failureCallback)
        }
    }
    
    func stop() {
        logger.log("Stopping combo whisper transport")
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
    
    func send(remote: Listener, chunks: [TextProtocol.ProtocolChunk]) {
        guard let remote = listeners[remote.id] else {
            fatalError("Targeting a remote that's not a listener: \(remote.id)")
        }
        switch remote.owner {
        case .auto:
            autoTransport?.send(remote: remote.inner as! AutoRemote, chunks: chunks)
        case .manual:
            manualTransport!.send(remote: remote.inner as! ManualRemote, chunks: chunks)
        }
    }
    
    func drop(remote: Listener) {
        guard let listener = listeners[remote.id] else {
            fatalError("Dropping a remote that's not a listener: \(remote.id)")
        }
        switch remote.owner {
        case .auto:
            autoTransport?.drop(remote: listener.inner as! AutoRemote)
        case .manual:
            manualTransport?.drop(remote: listener.inner as! ManualRemote)
        }
    }
    
    func publish(chunks: [TextProtocol.ProtocolChunk]) {
        autoTransport?.publish(chunks: chunks)
        manualTransport?.publish(chunks: chunks)
    }
    
    // MARK: internal types, properties, and initialization
    typealias AutoTransport = BluetoothWhisperTransport
    typealias AutoRemote = BluetoothWhisperTransport.Remote
    typealias ManualTransport = TcpWhisperTransport
    typealias ManualRemote = TcpWhisperTransport.Remote

    enum Owner {
        case auto
        case manual
    }
    
    final class Listener: TransportRemote {
        let id: String
        var name: String
        var owner: Owner

        fileprivate var inner: (any TransportRemote)
        
        init(owner: Owner, inner: any TransportRemote) {
            self.owner = owner
            self.inner = inner
            self.id = inner.id
            self.name = inner.name
        }
    }
    
    private var autoFactory = BluetoothFactory.shared
    private var autoStatus: TransportStatus = .off
    private var autoTransport: AutoTransport?
    private var manualFactory = TcpFactory.shared
    private var manualStatus: TransportStatus = .off
    private var manualTransport: TcpWhisperTransport?
    private var listeners: [String: Listener] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var publisherUrl: TransportUrl
    private var failureCallback: ((String) -> Void)?

    init(_ publisherUrl: TransportUrl) {
        logger.log("Initializing combo whisper transport")
        self.publisherUrl = publisherUrl
        self.autoFactory.statusSubject
            .sink(receiveValue: setAutoStatus)
            .store(in: &cancellables)
        self.manualFactory.statusSubject
            .sink(receiveValue: setManualStatus)
            .store(in: &cancellables)
    }
    
    deinit {
        logger.log("Destroying combo whisper transport")
        cancellables.cancel()
    }
    
    //MARK: internal methods
    private func setAutoStatus(_ status: TransportStatus) {
        guard autoStatus != status else {
            return
        }
        if autoStatus == .on {
            logger.error("The Bluetooth connection was available but has dropped")
            failureCallback?("The Bluetooth network has become unavailable")
        }
        autoStatus = status
    }
    
    private func setManualStatus(_ status: TransportStatus) {
        guard manualStatus != status else {
            return
        }
        if manualStatus == .on {
            logger.error("The Internet connection was available but has dropped")
            failureCallback?("The Internet connection has become unavailable")
        }
        manualStatus = status
    }
    
    private func initializeTransports() {
        if autoStatus == .on {
            self.autoTransport = AutoTransport()
            self.autoTransport?.addRemoteSubject
                .sink { [weak self] in self?.addListener(.auto, remote: $0) }
                .store(in: &cancellables)
            self.autoTransport?.dropRemoteSubject
                .sink { [weak self] in self?.removeListener(.auto, remote: $0) }
                .store(in: &cancellables)
            self.autoTransport?.receivedChunkSubject
                .sink { [weak self] in self?.receiveChunk($0) }
                .store(in: &cancellables)
        }
        if manualStatus == .on, let url = publisherUrl {
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
        if autoTransport == nil && manualTransport == nil {
            logger.error("No transports available for whispering")
            failureCallback?("Cannot whisper unless one of Bluetooth or Internet is available")
        }
    }
    
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
