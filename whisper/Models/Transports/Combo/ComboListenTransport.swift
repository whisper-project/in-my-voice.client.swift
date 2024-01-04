// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine

final class ComboListenTransport: SubscribeTransport {
    // MARK: Protocol properties and methods
    typealias Remote = Whisperer
    
    var lostRemoteSubject: PassthroughSubject<Remote, Never> = .init()
	var contentSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()
	var controlSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()

    func start(failureCallback: @escaping (String) -> Void) {
        logger.info("Starting combo listen transport")
		staggerStart(failureCallback: failureCallback)
    }

    func stop() {
        logger.info("Stopping combo listen transport")
		staggerStop(.auto)
		staggerStop(.manual)
    }
    
    func goToBackground() {
        autoTransport?.goToBackground()
        manualTransport?.goToBackground()
    }
    
    func goToForeground() {
        autoTransport?.goToForeground()
        manualTransport?.goToForeground()
    }
    
    func sendControl(remote: Whisperer, chunk: WhisperProtocol.ProtocolChunk) {
        guard let remote = remotes[remote.id] else {
            fatalError("Targeting a remote that's not a whisperer: \(remote.id)")
        }
        switch remote.owner {
        case .auto:
            autoTransport!.sendControl(remote: remote.inner as! AutoRemote, chunk: chunk)
        case .manual:
            manualTransport!.sendControl(remote: remote.inner as! ManualRemote, chunk: chunk)
        }
    }

    func drop(remote: Whisperer) {
		guard let remote = remotes.removeValue(forKey: remote.id) else {
            fatalError("Dropping a remote that's not a whisperer: \(remote.id)")
        }
        switch remote.owner {
        case .auto:
            autoTransport!.drop(remote: remote.inner as! AutoRemote)
        case .manual:
            manualTransport!.drop(remote: remote.inner as! ManualRemote)
        }
    }

	func subscribe(remote: Whisperer, conversation: Conversation) {
        guard let remote = remotes[remote.id] else {
            fatalError("Subscribing to an unknown remote: \(remote.id)")
        }
        switch remote.owner {
        case .auto:
			logger.info("Subscribing to an AutoRemote: \(remote.id)")
			staggerStop(.manual)
			autoTransport!.subscribe(remote: remote.inner as! AutoRemote, conversation: conversation)
        case .manual:
			logger.info("Subscribing to a ManualRemote: \(remote.id)")
			staggerStop(.auto)
            manualTransport!.subscribe(remote: remote.inner as! ManualRemote, conversation: conversation)
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
		var id: String { get { inner.id } }
		var kind: TransportKind { get {inner.kind} }
		private(set) var owner: Owner

        fileprivate var inner: (any TransportRemote)
        
        init(owner: Owner, inner: any TransportRemote) {
            self.owner = owner
            self.inner = inner
        }
    }
    
    private var autoTransport: AutoTransport?
    private var manualTransport: ManualTransport?
	private var staggerTimer: Timer?
    private var remotes: [String: Whisperer] = [:]
    private var cancellables: Set<AnyCancellable> = []
    
    init(_ conversation: Conversation?) {
        logger.log("Initializing combo listen transport")
        if let c = conversation {
            let manualTransport = ManualTransport(c)
            self.manualTransport = manualTransport
            manualTransport.lostRemoteSubject
                .sink { [weak self] in self?.removeListener(.manual, remote: $0) }
                .store(in: &cancellables)
			manualTransport.contentSubject
				.sink { [weak self] in self?.receiveContentChunk($0) }
				.store(in: &cancellables)
			manualTransport.controlSubject
				.sink { [weak self] in self?.receiveControlChunk(.manual, remote: $0.remote, chunk: $0.chunk) }
				.store(in: &cancellables)
        }
		let autoTransport = AutoTransport(conversation)
		self.autoTransport = autoTransport
		autoTransport.lostRemoteSubject
			.sink { [weak self] in self?.removeListener(.auto, remote: $0) }
			.store(in: &cancellables)
		autoTransport.contentSubject
			.sink { [weak self] in self?.receiveContentChunk($0) }
			.store(in: &cancellables)
		autoTransport.controlSubject
			.sink { [weak self] in self?.receiveControlChunk(.manual, remote: $0.remote, chunk: $0.chunk) }
			.store(in: &cancellables)
    }
    
    deinit {
        logger.log("Destroying combo listen transport")
        cancellables.cancel()
    }
    
    //MARK: internal methods
	private func staggerStart(failureCallback: @escaping (String) -> Void) {
		guard let auto = autoTransport else {
			fatalError("Cannot start Bluetooth transport?")
		}
		logger.info("Starting Bluetooth in advance of Network")
		auto.start(failureCallback: failureCallback)
		staggerTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(listenerWaitTime), repeats: false) { _ in
			// run loop will invalidate the timer
			self.staggerTimer = nil
			#if DEBUG
			if let manual = self.manualTransport {
				manual.start(failureCallback: failureCallback)
			}
			#endif
		}
	}

	private func staggerStop(_ kind: Owner) {
		if let timer = staggerTimer {
			staggerTimer = nil
			timer.invalidate()
		}
		switch kind {
		case .auto:
			autoTransport?.stop()
		case .manual:
			manualTransport?.stop()
		}
	}

	private func removeListener(_ owner: Owner, remote: any TransportRemote) {
        guard let removed = remotes.removeValue(forKey: remote.id) else {
            logger.error("Ignoring drop of unknown remote \(remote.id)")
            return
        }
        lostRemoteSubject.send(removed)
    }
    
    private func receiveContentChunk(_ pair: (remote: any TransportRemote, chunk: WhisperProtocol.ProtocolChunk)) {
		// we should already have the Whisperer as a remote
        guard let remote = remotes[pair.remote.id] else {
            logger.error("Ignoring chunk from unknown remote \(pair.remote.id)")
            return
        }
        contentSubject.send((remote: remote, chunk: pair.chunk))
    }

	private func receiveControlChunk(_ owner: Owner, remote: any TransportRemote, chunk: WhisperProtocol.ProtocolChunk) {
		if let remote = remotes[remote.id] {
			controlSubject.send((remote: remote, chunk: chunk))
		} else {
			let whisperer = Whisperer(owner: owner, inner: remote)
			remotes[remote.id] = whisperer
			contentSubject.send((remote: whisperer, chunk: chunk))
		}
	}
}
