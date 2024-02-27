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
    
    func sendControl(remote: Remote, chunk: WhisperProtocol.ProtocolChunk) {
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

	func drop(remote: Remote) {
		guard let remote = remotes.removeValue(forKey: remote.id) else {
			fatalError("Dropping an unknown remote: \(remote.id)")
		}
		clients.removeValue(forKey: remote.clientId)
		switch remote.kind {
		case .local:
			localTransport?.drop(remote: remote.inner as! LocalRemote)
		case .global:
			globalTransport?.drop(remote: remote.inner as! GlobalRemote)
		}
	}

	func subscribe(remote: Remote, conversation: ListenConversation) {
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
		let id: String
		let kind: TransportKind

        fileprivate var inner: (any TransportRemote)
		fileprivate var clientId: String

		init(inner: any TransportRemote, clientId: String) {
			self.inner = inner
			self.id = inner.id
			self.kind = inner.kind
			self.clientId = clientId
		}
    }
    
	private var conversation: ListenConversation?
	private var localFactory = BluetoothFactory.shared
	private var localStatus: TransportStatus = .off
	private var localTransport: LocalTransport?
	private var globalFactory = TcpFactory.shared
	private var globalStatus: TransportStatus = .off
	private var globalTransport: GlobalTransport?
	private var staggerTimer: Timer?
	private var remotes: [String: Remote] = [:]	// maps from remote id to remote
	private var clients: [String: Remote] = [:]	// maps from client id to remote
    private var cancellables: Set<AnyCancellable> = []
	private var failureCallback: ((String) -> Void)?

    init(_ conversation: ListenConversation?) {
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
		#if DISABLE_BLUETOOTH
		localStatus = .off
		#else
		if localStatus == .on {
			logger.error("The Bluetooth connection was available but has dropped")
			// don't fail because this happens when we sleep and it comes back.
			// failureCallback?("The Bluetooth network has become unavailable")
		}
		localStatus = status
		#endif
	}

	private func setGlobalStatus(_ status: TransportStatus) {
		guard globalStatus != status else {
			return
		}
		#if DISABLE_INTERNET
		globalStatus = .off
		#else
		if globalStatus == .on {
			logger.error("The Internet connection was available but has dropped")
			failureCallback?("The Internet connection has become unavailable")
		}
		globalStatus = status
		#endif
	}

	private func initializeTransports() {
		if let c = conversation, globalStatus == .on {
			let globalTransport = GlobalTransport(c)
			self.globalTransport = globalTransport
			globalTransport.lostRemoteSubject
				.sink { [weak self] in self?.removeRemote(remote: $0) }
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
				.sink { [weak self] in self?.removeRemote(remote: $0) }
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
		if let local = localTransport {
			logger.info("Starting Bluetooth in advance of Internet")
			local.start(failureCallback: failureCallback!)
			staggerTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(listenerWaitTime), repeats: false) { _ in
				// run loop will invalidate the timer
				self.staggerTimer = nil
				if let global = self.globalTransport {
					logger.info("Starting Internet after Bluetooth")
					global.start(failureCallback: self.failureCallback!)
				}
			}
		} else if let global = globalTransport {
			logger.info("Starting Internet only because Bluetooth not available")
			global.start(failureCallback: self.failureCallback!)
		} else {
			fatalError("Cannot listen because neither Bluetooth nor Internet is available")
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

	private func removeRemote(remote: any TransportRemote) {
		guard let removed = remotes.removeValue(forKey: remote.id) else {
			logger.error("Ignoring drop of unknown \(remote.kind, privacy: .public) remote \(remote.id, privacy: .public)")
			return
		}
		clients.removeValue(forKey: removed.clientId)
		lostRemoteSubject.send(removed)
	}

    private func receiveContentChunk(_ pair: (remote: any TransportRemote, chunk: WhisperProtocol.ProtocolChunk)) {
		// we should already have the Whisperer as a remote
        guard let remote = remotes[pair.remote.id] else {
			logger.error("Ignoring chunk from \(pair.remote.kind, privacy: .public) unknown remote \(pair.remote.id, privacy: .public)")
            return
        }
        contentSubject.send((remote: remote, chunk: pair.chunk))
    }

	private func receiveControlChunk(remote: any TransportRemote, chunk: WhisperProtocol.ProtocolChunk) {
		if let remote = remoteFor(remote: remote, chunk: chunk) {
			controlSubject.send((remote: remote, chunk: chunk))
		}
	}

	private func remoteFor(remote: any TransportRemote, chunk: WhisperProtocol.ProtocolChunk) -> Remote? {
		if let remote = remotes[remote.id] {
			return remote
		}
		guard chunk.isPresenceMessage(), let info = WhisperProtocol.ClientInfo.fromString(chunk.text) else {
			fatalError("Non-presence initial control packet received from \(remote.kind) remote: \(remote.id)")
		}
		guard clients[info.clientId] == nil else {
			logger.info("Refusing second appearance of client via different network: \(remote.kind)")
			switch remote.kind {
			case .local:
				localTransport?.drop(remote: remote as! LocalRemote)
			case .global:
				globalTransport?.drop(remote: remote as! GlobalRemote)
			}
			return nil
		}
		let remote = Wrapper(inner: remote, clientId: info.clientId)
		remotes[remote.id] = remote
		clients[info.clientId] = remote
		return remote
	}
}
