// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine

final class ComboWhisperTransport: PublishTransport {
    // MARK: protocol properties and methods
    typealias Remote = Wrapper
    
    var lostRemoteSubject: PassthroughSubject<Remote, Never> = .init()
	var controlSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()
	var contentSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()

    func start(failureCallback: @escaping (String) -> Void) {
        logger.log("Starting combo whisper transport")
        self.failureCallback = failureCallback
        initializeTransports()
        if let local = localTransport {
            local.start(failureCallback: failureCallback)
        }
        if let global = globalTransport {
            global.start(failureCallback: failureCallback)
        }
    }
    
    func stop() {
        logger.log("Stopping combo whisper transport")
        localTransport?.stop()
        globalTransport?.stop()
    }
    
    func goToBackground() {
        localTransport?.goToBackground()
        globalTransport?.goToBackground()
    }
    
    func goToForeground() {
        localTransport?.goToForeground()
        globalTransport?.goToForeground()
    }
    
    func sendContent(remote: Remote, chunks: [WhisperProtocol.ProtocolChunk]) {
        guard let remote = remotes[remote.id] else {
            fatalError("Sending content to an unknown remote: \(remote.id)")
        }
        switch remote.kind {
        case .local:
            localTransport?.sendContent(remote: remote.inner as! LocalRemote, chunks: chunks)
        case .global:
            globalTransport?.sendContent(remote: remote.inner as! GlobalRemote, chunks: chunks)
        }
    }

    func sendControl(remote: Remote, chunk: WhisperProtocol.ProtocolChunk) {
        guard let remote = remotes[remote.id] else {
            fatalError("Sending control to an unknown remote: \(remote.id)")
        }
        switch remote.kind {
        case .local:
            localTransport?.sendControl(remote: remote.inner as! LocalRemote, chunk: chunk)
        case .global:
            globalTransport?.sendControl(remote: remote.inner as! GlobalRemote, chunk: chunk)
        }
    }

    func drop(remote: Remote) {
		guard let remote = remotes.removeValue(forKey: remote.id) else {
            fatalError("Dropping an unknown remote: \(remote.id)")
        }
        switch remote.kind {
        case .local:
            localTransport?.drop(remote: remote.inner as! LocalRemote)
        case .global:
            globalTransport?.drop(remote: remote.inner as! GlobalRemote)
        }
    }
    
	func authorize(remote: Wrapper) {
		guard let remote = remotes[remote.id] else {
			fatalError("Authorizing an unknown remote: \(remote.id)")
		}
		switch remote.kind {
		case .local:
			localTransport?.authorize(remote: remote.inner as! LocalRemote)
		case .global:
			globalTransport?.authorize(remote: remote.inner as! GlobalRemote)
		}
	}

	func deauthorize(remote: Wrapper) {
		guard let remote = remotes[remote.id] else {
			fatalError("Deauthorizing an unknown remote: \(remote.id)")
		}
		switch remote.kind {
		case .local:
			localTransport?.deauthorize(remote: remote.inner as! LocalRemote)
		case .global:
			globalTransport?.deauthorize(remote: remote.inner as! GlobalRemote)
		}
	}

    func publish(chunks: [WhisperProtocol.ProtocolChunk]) {
        localTransport?.publish(chunks: chunks)
        globalTransport?.publish(chunks: chunks)
    }
    
    // MARK: internal types, properties, and initialization
    typealias LocalTransport = BluetoothWhisperTransport
    typealias LocalRemote = BluetoothWhisperTransport.Remote
    typealias GlobalTransport = TcpWhisperTransport
    typealias GlobalRemote = TcpWhisperTransport.Remote

    final class Wrapper: TransportRemote {
        var id: String { get { inner.id } }
        var kind: TransportKind

		fileprivate var inner: (any TransportRemote)

        init(inner: any TransportRemote) {
            self.inner = inner
			self.kind = inner.kind
        }
    }
    
    private var localFactory = BluetoothFactory.shared
    private var localStatus: TransportStatus = .off
    private var localTransport: LocalTransport?
    private var globalFactory = TcpFactory.shared
    private var globalStatus: TransportStatus = .off
    private var globalTransport: TcpWhisperTransport?
    private var remotes: [String: Remote] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var conversation: Conversation
    private var failureCallback: ((String) -> Void)?

    init(_ c: Conversation) {
        logger.log("Initializing combo whisper transport")
        self.conversation = c
        self.localFactory.statusSubject
            .sink(receiveValue: setLocalStatus)
            .store(in: &cancellables)
        self.globalFactory.statusSubject
            .sink(receiveValue: setGlobalStatus)
            .store(in: &cancellables)
    }
    
    deinit {
        logger.log("Destroying combo whisper transport")
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
		if globalStatus == .on {
			logger.error("The Internet connection was available but has dropped")
			failureCallback?("The Internet connection has become unavailable")
		}
        globalStatus = status
    }
    
    private func initializeTransports() {
        if localStatus == .on {
            let localTransport = LocalTransport(conversation)
            self.localTransport = localTransport
            localTransport.lostRemoteSubject
                .sink { [weak self] in self?.removeRemote(remote: $0) }
                .store(in: &cancellables)
            localTransport.controlSubject
                .sink { [weak self] in self?.receiveControl($0) }
                .store(in: &cancellables)
        }
        if globalStatus == .on {
			let globalTransport = GlobalTransport(conversation)
			self.globalTransport = globalTransport
			globalTransport.lostRemoteSubject
				.sink { [weak self] in self?.removeRemote(remote: $0) }
				.store(in: &cancellables)
			globalTransport.controlSubject
				.sink { [weak self] in self?.receiveControl($0) }
				.store(in: &cancellables)
        }
        if localTransport == nil && globalTransport == nil {
            logger.error("No transports available for whispering")
            failureCallback?("Cannot whisper unless one of Bluetooth or WiFi is available")
        }
    }
    
    private func removeRemote(remote: any TransportRemote) {
        guard let removed = remotes.removeValue(forKey: remote.id) else {
            logger.error("Ignoring drop of unknown remote \(remote.id)")
            return
        }
        lostRemoteSubject.send(removed)
    }
    
    private func receiveControl(_ pair: (remote: any TransportRemote, chunk: WhisperProtocol.ProtocolChunk)) {
		controlSubject.send((remote: ensureRemote(remote: pair.remote), chunk: pair.chunk))
    }

	private func ensureRemote(remote: any TransportRemote) -> Remote {
		if let wrapper = remotes[remote.id] {
			return wrapper
		}
		let wrapper = Wrapper(inner: remote)
		remotes[remote.id] = wrapper
		return wrapper
	}
}
