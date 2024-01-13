// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine

final class ComboListenTransport: SubscribeTransport {
    // MARK: Protocol properties and methods
    typealias Remote = Wrapper
    
    var lostRemoteSubject: PassthroughSubject<Remote, Never> = .init()
	var contentSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()
	var controlSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()

    func start(failureCallback: @escaping (String) -> Void) {
        logger.info("Starting combo listen transport")
		self.failureCallback = failureCallback
		initializeTransports()
		staggerStart()
    }

    func stop() {
        logger.info("Stopping combo listen transport")
		staggerStop(.local)
		staggerStop(.global)
    }
    
    func goToBackground() {
        localTransport?.goToBackground()
        globalTransport?.goToBackground()
    }
    
    func goToForeground() {
        localTransport?.goToForeground()
        globalTransport?.goToForeground()
    }
    
    func sendControl(remote: Wrapper, chunk: WhisperProtocol.ProtocolChunk) {
        guard let remote = remotes[remote.id] else {
            fatalError("Targeting a remote that's not a whisperer: \(remote.id)")
        }
        switch remote.kind {
        case .local:
            localTransport!.sendControl(remote: remote.inner as! LocalRemote, chunk: chunk)
        case .global:
            globalTransport!.sendControl(remote: remote.inner as! GlobalRemote, chunk: chunk)
        }
    }

    func drop(remote: Wrapper) {
		guard let remote = remotes.removeValue(forKey: remote.id) else {
            fatalError("Request to drop an unknown remote: \(remote.id)")
        }
        switch remote.kind {
        case .local:
            localTransport!.drop(remote: remote.inner as! LocalRemote)
        case .global:
            globalTransport!.drop(remote: remote.inner as! GlobalRemote)
        }
    }

	func subscribe(remote: Wrapper, conversation: Conversation) {
        guard let remote = remotes[remote.id] else {
            fatalError("Subscribing to an unknown remote: \(remote.id)")
        }
        switch remote.kind {
        case .local:
			logger.info("Subscribing to a LocalRemote: \(remote.id)")
			staggerStop(.global)
			localTransport!.subscribe(remote: remote.inner as! LocalRemote, conversation: conversation)
        case .global:
			logger.info("Subscribing to a GlobalRemote: \(remote.id)")
			staggerStop(.local)
            globalTransport!.subscribe(remote: remote.inner as! GlobalRemote, conversation: conversation)
        }
    }
    
    // MARK: Internal types, properties, and initialization
    typealias LocalTransport = BluetoothListenTransport
    typealias LocalRemote = BluetoothListenTransport.Remote
    typealias GlobalTransport = TcpListenTransport
    typealias GlobalRemote = TcpListenTransport.Remote
    
    enum Owner {
        case local
        case global
    }
    
    final class Wrapper: TransportRemote {
		var id: String { get { inner.id } }
		var kind: TransportKind { get {inner.kind} }

        fileprivate var inner: (any TransportRemote)
        
        init(inner: any TransportRemote) {
            self.inner = inner
        }
    }
    
	private var conversation: Conversation?
	private var localFactory = BluetoothFactory.shared
	private var localStatus: TransportStatus = .off
	private var localTransport: LocalTransport?
	private var globalFactory = TcpFactory.shared
	private var globalStatus: TransportStatus = .off
	private var globalTransport: GlobalTransport?
	private var staggerTimer: Timer?
    private var remotes: [String: Wrapper] = [:]
    private var cancellables: Set<AnyCancellable> = []
	private var failureCallback: ((String) -> Void)?

    init(_ conversation: Conversation?) {
        logger.log("Initializing combo listen transport")
		self.conversation = conversation
		self.localFactory.statusSubject
			.sink(receiveValue: setLocalStatus)
			.store(in: &cancellables)
		self.globalFactory.statusSubject
			.sink(receiveValue: setGlobalStatus)
			.store(in: &cancellables)
    }
    
    deinit {
        logger.log("Destroying combo listen transport")
        cancellables.cancel()
    }
    
    //MARK: internal methods
	private func setLocalStatus(_ status: TransportStatus) {
		guard localStatus != status else {
			return
		}
		if localStatus == .on {
			logger.error("The Bluetooth connection was available but has dropped")
			failureCallback?("The Bluetooth network has become unavailable")
		}
		localStatus = status
	}

	private func setGlobalStatus(_ status: TransportStatus) {
		guard globalStatus != status else {
			return
		}
#if DEBUG
		globalStatus = .off
#else
		if globalStatus == .on {
			logger.error("The Internet connection was available but has dropped")
			failureCallback?("The Internet connection has become unavailable")
		}
		globalStatus = isPending
#endif
	}

	private func initializeTransports() {
		if let c = conversation, globalStatus == .on {
			let globalTransport = GlobalTransport(c)
			self.globalTransport = globalTransport
			globalTransport.lostRemoteSubject
				.sink { [weak self] in self?.removeListener(remote: $0) }
				.store(in: &cancellables)
			globalTransport.contentSubject
				.sink { [weak self] in self?.receiveContentChunk($0) }
				.store(in: &cancellables)
			globalTransport.controlSubject
				.sink { [weak self] in self?.receiveControlChunk(remote: $0.remote, chunk: $0.chunk) }
				.store(in: &cancellables)
		}
		if localStatus == .on {
			let localTransport = LocalTransport(conversation)
			self.localTransport = localTransport
			localTransport.lostRemoteSubject
				.sink { [weak self] in self?.removeListener(remote: $0) }
				.store(in: &cancellables)
			localTransport.contentSubject
				.sink { [weak self] in self?.receiveContentChunk($0) }
				.store(in: &cancellables)
			localTransport.controlSubject
				.sink { [weak self] in self?.receiveControlChunk(remote: $0.remote, chunk: $0.chunk) }
				.store(in: &cancellables)
		}
		if localTransport == nil && globalTransport == nil {
			logger.error("No transports available for whispering")
			failureCallback?("Cannot whisper unless one of Bluetooth or WiFi is available")
		}
	}

	private func staggerStart() {
		guard let local = localTransport else {
			fatalError("Cannot start Bluetooth transport?")
		}
		logger.info("Starting Bluetooth in advance of Network")
		local.start(failureCallback: failureCallback!)
		staggerTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(listenerWaitTime), repeats: false) { _ in
			// run loop will invalidate the timer
			self.staggerTimer = nil
			if let global = self.globalTransport {
				global.start(failureCallback: self.failureCallback!)
			}
		}
	}

	private func staggerStop(_ kind: Owner) {
		if let timer = staggerTimer {
			staggerTimer = nil
			timer.invalidate()
		}
		switch kind {
		case .local:
			localTransport?.stop()
		case .global:
			globalTransport?.stop()
		}
	}

	private func removeListener(remote: any TransportRemote) {
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

	private func receiveControlChunk(remote: any TransportRemote, chunk: WhisperProtocol.ProtocolChunk) {
		if let remote = remotes[remote.id] {
			controlSubject.send((remote: remote, chunk: chunk))
		} else {
			let whisperer = Wrapper(inner: remote)
			remotes[remote.id] = whisperer
			controlSubject.send((remote: whisperer, chunk: chunk))
		}
	}
}
