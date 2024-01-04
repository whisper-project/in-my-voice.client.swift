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
    
    func sendContent(remote: Remote, chunks: [WhisperProtocol.ProtocolChunk]) {
        guard let remote = remotes[remote.id] else {
            fatalError("Sending content to an unknown remote: \(remote.id)")
        }
        switch remote.owner {
        case .auto:
            autoTransport?.sendContent(remote: remote.inner as! AutoRemote, chunks: chunks)
        case .manual:
            manualTransport?.sendContent(remote: remote.inner as! ManualRemote, chunks: chunks)
        }
    }

    func sendControl(remote: Remote, chunk: WhisperProtocol.ProtocolChunk) {
        guard let remote = remotes[remote.id] else {
            fatalError("Sending control to an unknown remote: \(remote.id)")
        }
        switch remote.owner {
        case .auto:
            autoTransport?.sendControl(remote: remote.inner as! AutoRemote, chunk: chunk)
        case .manual:
            manualTransport?.sendControl(remote: remote.inner as! ManualRemote, chunk: chunk)
        }
    }

    func drop(remote: Remote) {
		guard let remote = remotes.removeValue(forKey: remote.id) else {
            fatalError("Dropping an unknown remote: \(remote.id)")
        }
        switch remote.owner {
        case .auto:
            autoTransport?.drop(remote: remote.inner as! AutoRemote)
        case .manual:
            manualTransport?.drop(remote: remote.inner as! ManualRemote)
        }
    }
    
    func publish(chunks: [WhisperProtocol.ProtocolChunk]) {
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
    
    final class Wrapper: TransportRemote {
        var id: String { get { inner.id } }
        var authorized: Bool { get { inner.authorized } set(val) { inner.authorized = val } }
		private(set) var owner: Owner

		fileprivate var inner: (any TransportRemote)

        init(owner: Owner, inner: any TransportRemote) {
            self.owner = owner
            self.inner = inner
        }
    }
    
    private var autoFactory = BluetoothFactory.shared
    private var autoStatus: TransportStatus = .off
    private var autoTransport: AutoTransport?
    private var manualFactory = TcpFactory.shared
    private var manualStatus: TransportStatus = .off
    private var manualTransport: TcpWhisperTransport?
    private var remotes: [String: Remote] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var conversation: Conversation
    private var failureCallback: ((String) -> Void)?

    init(_ c: Conversation) {
        logger.log("Initializing combo whisper transport")
        self.conversation = c
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
		#if DEBUG
		manualStatus = .off
		#else
		if manualStatus == .on {
			logger.error("The Internet connection was available but has dropped")
			failureCallback?("The Internet connection has become unavailable")
		}
        manualStatus = isPending
		#endif
    }
    
    private func initializeTransports() {
        if autoStatus == .on {
            let autoTransport = AutoTransport(conversation)
            self.autoTransport = autoTransport
            autoTransport.lostRemoteSubject
                .sink { [weak self] in self?.removeListener(.auto, remote: $0) }
                .store(in: &cancellables)
            autoTransport.controlSubject
                .sink { [weak self] in self?.receiveControl($0) }
                .store(in: &cancellables)
        }
        if manualStatus == .on {
			let manualTransport = ManualTransport(conversation)
			self.manualTransport = manualTransport
			manualTransport.lostRemoteSubject
				.sink { [weak self] in self?.removeListener(.manual, remote: $0) }
				.store(in: &cancellables)
			manualTransport.controlSubject
				.sink { [weak self] in self?.receiveControl($0) }
				.store(in: &cancellables)
        }
        if autoTransport == nil && manualTransport == nil {
            logger.error("No transports available for whispering")
            failureCallback?("Cannot whisper unless one of Bluetooth or WiFi is available")
        }
    }
    
    private func removeListener(_ owner: Owner, remote: any TransportRemote) {
        guard let removed = remotes.removeValue(forKey: remote.id) else {
            logger.error("Ignoring drop of unknown remote \(remote.id)")
            return
        }
        lostRemoteSubject.send(removed)
    }
    
    private func receiveControl(_ pair: (remote: any TransportRemote, chunk: WhisperProtocol.ProtocolChunk)) {
        guard let remote = remotes[pair.remote.id] else {
            logger.error("Ignoring control chunk from unknown remote \(pair.remote.id)")
            return
        }
        controlSubject.send((remote: remote, chunk: pair.chunk))
    }
}
