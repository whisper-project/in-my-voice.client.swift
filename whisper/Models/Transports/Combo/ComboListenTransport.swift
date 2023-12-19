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
	var contentSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()
	var controlSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()

    func start(failureCallback: @escaping (String) -> Void) {
        logger.info("Starting combo listen transport")
        if let auto = autoTransport {
            auto.start(failureCallback: failureCallback)
        } else {
            manualTransport!.start(failureCallback: failureCallback)
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
    
    func sendControl(remote: Whisperer, chunks: [WhisperProtocol.ProtocolChunk]) {
        guard let remote = remotes[remote.id] else {
            fatalError("Targeting a remote that's not a whisperer: \(remote.id)")
        }
        switch remote.owner {
        case .auto:
            autoTransport!.sendControl(remote: remote.inner as! AutoRemote, chunks: chunks)
        case .manual:
            manualTransport!.sendControl(remote: remote.inner as! ManualRemote, chunks: chunks)
        }
    }

    func drop(remote: Whisperer) {
        guard let remote = remotes[remote.id] else {
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
        guard let remote = remotes[remote.id] else {
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
    typealias AutoTransport = BluetoothListenTransport
    typealias AutoRemote = BluetoothListenTransport.Remote
    typealias ManualTransport = TcpListenTransport
    typealias ManualRemote = TcpListenTransport.Remote
    
    enum Owner {
        case auto
        case manual
    }
    
    final class Whisperer: TransportRemote {
		var id: String {get { inner.id }}
		var name: String {get { inner.name }}
		var authorized: Bool { get { inner.authorized } set(val) { inner.authorized = val }}
		private(set) var owner: Owner

        fileprivate var inner: (any TransportRemote)
        
        init(owner: Owner, inner: any TransportRemote) {
            self.owner = owner
            self.inner = inner
        }
    }
    
    private var autoTransport: AutoTransport?
    private var manualTransport: ManualTransport?
    private var remotes: [String: Whisperer] = [:]
    private var cancellables: Set<AnyCancellable> = []
    
    init(_ conversation: Conversation?) {
        logger.log("Initializing combo listen transport")
        if let c = conversation {
            let manualTransport = ManualTransport(c)
            self.manualTransport = manualTransport
            manualTransport.addRemoteSubject
                .sink { [weak self] in self?.addListener(.manual, remote: $0) }
                .store(in: &cancellables)
            manualTransport.dropRemoteSubject
                .sink { [weak self] in self?.removeListener(.manual, remote: $0) }
                .store(in: &cancellables)
			manualTransport.contentSubject
				.sink { [weak self] in self?.receiveContentChunk($0) }
				.store(in: &cancellables)
			manualTransport.controlSubject
				.sink { [weak self] in self?.receiveControlChunk($0) }
				.store(in: &cancellables)
        }
		let autoTransport = AutoTransport(conversation)
		self.autoTransport = autoTransport
		autoTransport.addRemoteSubject
			.sink { [weak self] in self?.addListener(.auto, remote: $0) }
			.store(in: &cancellables)
		autoTransport.dropRemoteSubject
			.sink { [weak self] in self?.removeListener(.auto, remote: $0) }
			.store(in: &cancellables)
		autoTransport.contentSubject
			.sink { [weak self] in self?.receiveContentChunk($0) }
			.store(in: &cancellables)
    }
    
    deinit {
        logger.log("Destroying combo listen transport")
        cancellables.cancel()
    }
    
    //MARK: internal methods
    private func addListener(_ owner: Owner, remote: any TransportRemote) {
        guard remotes[remote.id] == nil else {
            logger.error("Ignoring add of existing remote \(remote.id) with name \(remote.name)")
            return
        }
        let whisperer = Whisperer(owner: owner, inner: remote)
        remotes[remote.id] = whisperer
        addRemoteSubject.send(whisperer)
    }
    
    private func removeListener(_ owner: Owner, remote: any TransportRemote) {
        guard let removed = remotes.removeValue(forKey: remote.id) else {
            logger.error("Ignoring drop of unknown remote \(remote.id) with name \(remote.name)")
            return
        }
        dropRemoteSubject.send(removed)
    }
    
    private func receiveContentChunk(_ pair: (remote: any TransportRemote, chunk: WhisperProtocol.ProtocolChunk)) {
        guard let remote = remotes[pair.remote.id] else {
            logger.error("Ignoring chunk from unknown remote \(pair.remote.id) with name \(pair.remote.name)")
            return
        }
        contentSubject.send((remote: remote, chunk: pair.chunk))
    }

	private func receiveControlChunk(_ pair: (remote: any TransportRemote, chunk: WhisperProtocol.ProtocolChunk)) {
		guard let remote = remotes[pair.remote.id] else {
			logger.error("Ignoring chunk from unknown remote \(pair.remote.id) with name \(pair.remote.name)")
			return
		}
		controlSubject.send((remote: remote, chunk: pair.chunk))
	}
}
