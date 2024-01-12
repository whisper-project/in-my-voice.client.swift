// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Combine
import CoreBluetooth

final class BluetoothWhisperTransport: PublishTransport {
    // MARK: Protocol properties and methods
    typealias Remote = Listener
    
    var lostRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var contentSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()
    var controlSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()

    func start(failureCallback: @escaping (String) -> Void) {
        logger.log("Starting Bluetooth whisper transport...")
        whisperService = BluetoothData.whisperService()
        factory.publish(service: whisperService!)
        startDiscovery()
    }
    
    func stop() {
        logger.log("Stopping Bluetooth whisper transport...")
        stopDiscovery()
        leaveConversation()
        if let service = whisperService {
            factory.unpublish(service: service)
            whisperService = nil
        }
    }
    
    func goToBackground() {
        guard !isInBackground else {
            return
        }
        isInBackground = true
        stopDiscovery()
    }
    
    func goToForeground() {
        guard isInBackground else {
            return
        }
        isInBackground = false
        startDiscovery()
    }
    
	func sendControl(remote: Remote, chunk: WhisperProtocol.ProtocolChunk) {
		if var existing = directedControl[remote.central] {
			existing.append(chunk)
		} else {
			directedControl[remote.central] = [chunk]
		}
		updateControlAndContent()
	}

    func drop(remote: Remote) {
		guard let existing = remotes[remote.central] else {
            logger.error("Ignoring drop request for non-remote: \(remote.id)")
            return
        }
		logger.info("Whisperer said to drop remote \(existing.id)")
		removeRemote(remote)
    }

	func authorize(remote: Remote) {
		guard let existing = remotes[remote.central] else {
			logger.error("Ignoring authorization for non-remote: \(remote.id)")
			return
		}
		remote.isAuthorized = true
		// in case they have already connected
		if let index = eavesdroppers.firstIndex(of: existing.central) {
			eavesdroppers.remove(at: index)
			listeners.append(existing.central)
		}
	}

	func deauthorize(remote: Remote) {
		guard let existing = remotes[remote.central] else {
			logger.error("Ignoring deauthorization for non-remote: \(remote.id)")
			return
		}
		remote.isAuthorized = false
		// in case they have already connected
		if let index = listeners.firstIndex(of: existing.central) {
			listeners.remove(at: index)
			// they are an eavesdropper until they disconnect or are re-authorized
			eavesdroppers.append(existing.central)
		}
	}

	func sendContent(remote: Remote, chunks: [WhisperProtocol.ProtocolChunk]) {
		if var existing = directedContent[remote.central] {
			existing.append(contentsOf: chunks)
		} else {
			directedContent[remote.central] = chunks
		}
		updateControlAndContent()
	}

    func publish(chunks: [WhisperProtocol.ProtocolChunk]) {
        for chunk in chunks {
            pendingContent.append(chunk)
        }
        updateContent()
    }
    
    // MARK: Peripheral Event Handlers

    private func noticeAd(_ pair: (CBPeripheral, [String: Any])) {
		guard !advertisers.contains(pair.0) else {
			// logger.debug("Ignoring repeat ads from existing advertiser")
			return
		}
		advertisers.append(pair.0)
        if let uuids = pair.1[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            if uuids.contains(BluetoothData.listenServiceUuid) {
                guard let adName = pair.1[CBAdvertisementDataLocalNameKey],
                      let id = adName as? String,
					  id == "discover" || id == BluetoothData.deviceId(conversation.id)
                else {
                    logger.error("Ignoring invalid advertisement from \(pair.0)")
                    return
                }
                logger.debug("Responding to ad from remote: \(pair.0)")
                startAdvertising()
            }
        }
    }
    
    private func noticeSubscription(_ pair: (CBCentral, CBCharacteristic)) {
		if pair.1.uuid == BluetoothData.controlOutUuid {
			// remote has opened the control channel
			let remote = ensureRemote(pair.0)
			remote.controlSubscribed = true
		} else if pair.1.uuid == BluetoothData.contentOutUuid {
			let remote = ensureRemote(pair.0)
			remote.contentSubscribed = true
			if remote.isAuthorized {
				// add this as an authorized listener
				logger.info("Adding content listener: \(remote.id)")
				listeners.append(pair.0)
			} else {
				// this is an eavesdropper
				logger.error("Found an eavesdropper: \(pair.0)")
				eavesdroppers.append(pair.0)
			}
		} else {
			logger.error("Ignoring subscribe for unexpected characteristic: \(pair.1)")
		}
    }
    
    private func noticeUnsubscription(_ pair: (CBCentral, CBCharacteristic)) {
		if let remote = remotes[pair.0] {
			// unexpected unsubscription, act as if the remote had dropped
			remote.hasDropped = true
			logger.error("Unsubscribe by remote \(remote.id) that hasn't dropped")
			removeRemote(remote)
			lostRemoteSubject.send(remote)
		}
		if let removed = removedRemotes[pair.0] {
			// unsubscription from a remote we have removed
			if pair.1.uuid == BluetoothData.contentOutUuid {
				removed.contentSubscribed = false
				if let index = eavesdroppers.firstIndex(of: pair.0) {
					eavesdroppers.remove(at: index)
				}
			} else if pair.1.uuid == BluetoothData.controlOutUuid {
				removed.controlSubscribed = false
			} else {
				logger.error("Got unsubscribe for a non-published characteristic: \(pair.1)")
			}
			if !removed.contentSubscribed && !removed.controlSubscribed {
				// the remote has fully disconnected, forget about it
				removedRemotes.removeValue(forKey: pair.0)
			}
		} else {
			logger.error("Ignoring unsubscribe from unknown central: \(pair.0.identifier.uuidString)")
        }
    }
    
    private func processReadRequest(_ request: CBATTRequest) {
        logger.log("Received read request \(request)...")
        guard request.offset == 0 else {
            logger.log("Read request has non-zero offset, ignoring it")
            factory.respondToReadRequest(request: request, withCode: .invalidOffset)
            return
        }
        let characteristic = request.characteristic
		logger.error("Got a read request for an unexpected characteristic: \(characteristic)")
		factory.respondToReadRequest(request: request, withCode: .attributeNotFound)
    }
    
    private func processWriteRequests(_ requests: [CBATTRequest]) {
        guard let request = requests.first else {
            fatalError("Got an empty write request sequence")
        }
        guard requests.count == 1 else {
            logger.error("Got multiple write requests in a batch: \(requests)")
            factory.respondToWriteRequest(request: request, withCode: .requestNotSupported)
            return
        }
		guard request.characteristic.uuid == BluetoothData.controlInUuid else {
            logger.error("Got a write request for an unexpected characteristic: \(request)")
            factory.respondToWriteRequest(request: request, withCode: .attributeNotFound)
            return
        }
        guard let value = request.value,
			  let chunk = WhisperProtocol.ProtocolChunk.fromData(value)
        else {
            logger.error("Ignoring a malformed packet: \(request)")
            factory.respondToWriteRequest(request: request, withCode: .unlikelyError)
			PreferenceData.bluetoothErrorCount += 1
            return
        }
		let remote = ensureRemote(request.central)
		if let value = WhisperProtocol.ControlOffset(rawValue: chunk.offset),
		   case .dropping = value {
			logger.info("Received \(value) message from: \(remote.id)")
			remote.hasDropped = true
			removeRemote(remote)
			lostRemoteSubject.send(remote)
			return
		}
		controlSubject.send((remote: remote, chunk: chunk))
        factory.respondToWriteRequest(request: request, withCode: .success)
    }
    
    private func updateControlAndContent() {
		if (updateControl()) {
			return
		}
        updateContent()
    }
    
    // MARK: Internal types, properties, and initialization
        
    final class Listener: TransportRemote {
        let id: String
		let kind: TransportKind = .local

        fileprivate var central: CBCentral
		fileprivate var profileId: String?
		fileprivate var contentSubscribed: Bool = false
		fileprivate var controlSubscribed: Bool = false
		fileprivate var isAuthorized: Bool = false
		fileprivate var hasDropped: Bool = false

        fileprivate init(central: CBCentral) {
            self.central = central
			self.id = central.identifier.uuidString
        }
    }

    private var factory = BluetoothFactory.shared
    private var remotes: [CBCentral: Remote] = [:]
	private var removedRemotes: [CBCentral: Remote] = [:]
    private var liveText: String = ""
    private var pendingContent: [WhisperProtocol.ProtocolChunk] = []
	private var directedContent: [CBCentral: [WhisperProtocol.ProtocolChunk]] = [:]
    private var directedControl: [CBCentral: [WhisperProtocol.ProtocolChunk]] = [:]
    private var advertisingInProgress = false
    private weak var adTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
	private var listeners: [CBCentral] = []
	private var eavesdroppers: [CBCentral] = []
    private var advertisers: [CBPeripheral] = []
    private var whisperService: CBMutableService?
    private var isInBackground = false
    private var conversation: Conversation

    init(_ c: Conversation) {
        logger.log("Initializing bluetooth whisper transport")
        conversation = c
        factory.advertisementSubject
            .sink { [weak self] in self?.noticeAd($0) }
            .store(in: &cancellables)
        factory.centralSubscribedSubject
            .sink { [weak self] in self?.noticeSubscription($0) }
            .store(in: &cancellables)
        factory.centralUnsubscribedSubject
            .sink { [weak self] in self?.noticeUnsubscription($0) }
            .store(in: &cancellables)
        factory.readRequestSubject
            .sink { [weak self] in self?.processReadRequest($0) }
            .store(in: &cancellables)
        factory.writeRequestSubject
            .sink { [weak self] in self?.processWriteRequests($0) }
            .store(in: &cancellables)
        factory.readyToUpdateSubject
            .sink { [weak self] _ in self?.updateControlAndContent() }
            .store(in: &cancellables)
    }
    
    deinit {
        logger.log("Destroying WhisperView model")
        cancellables.cancel()
    }

    //MARK: internal methods
    private func startDiscovery() {
        factory.scan(forServices: [BluetoothData.listenServiceUuid], allow_repeats: true)
		advertisers = []
        startAdvertising()
    }
    
    private func stopDiscovery() {
        stopAdvertising()
        factory.stopScan()
    }
    
    /// Send pending content to listeners; returns whether there more to send
    private func updateContent() {
        guard !remotes.isEmpty else {
            // logger.debug("No listeners to update, dumping pending changes")
			directedContent.removeAll()
            pendingContent.removeAll()
            return
        }
        // prioritize individuals over subscribers, because we want to finish
		// updating any specific listeners who are catching up before resuming
		// live updates to everyone
        if !directedContent.isEmpty {
            logger.log("Updating specific listeners...")
            while var (listener, chunks) = directedContent.first {
                while let chunk = chunks.first {
                    let sendOk = factory.updateValue(value: chunk.toData(),
                                                     characteristic: BluetoothData.contentOutCharacteristic,
                                                     central: listener)
                    if sendOk {
						chunks.removeFirst()
                        if chunks.isEmpty {
                            directedContent.removeValue(forKey: listener)
                        }
                    } else {
                        return
                    }
                }
            }
        }
		if !pendingContent.isEmpty {
            logger.debug("Updating subscribed listeners (\(self.pendingContent.count) chunks)...")
            while let chunk = pendingContent.first {
				let sendOk = eavesdroppers.isEmpty ?
							 factory.updateValue(value: chunk.toData(),
												 characteristic: BluetoothData.contentOutCharacteristic) :
							 factory.updateValue(value: chunk.toData(),
												 characteristic: BluetoothData.contentOutCharacteristic,
												 centrals: listeners)
                if sendOk {
                    pendingContent.removeFirst()
                } else {
                    return
                }
            }
        }
		return
    }

    /// Send pending control to listeners, returns whether there is more to send
    private func updateControl() -> Bool {
        guard !remotes.isEmpty else {
            // logger.debug("No listeners to update, dumping pending changes")
			directedControl.removeAll()
            return false
        }
        if !directedControl.isEmpty {
            while var (listener, chunks) = directedControl.first {
                while let chunk = chunks.first {
					logger.log("Sending control chunk: \(chunk)")
                    let sendOk = factory.updateValue(value: chunk.toData(),
                                                     characteristic: BluetoothData.controlOutCharacteristic,
                                                     central: listener)
                    if sendOk {
						chunks.removeFirst()
                        if chunks.isEmpty {
                            directedControl.removeValue(forKey: listener)
                        }
                    } else {
						logger.warning("Send failed for chunk: \(chunk)")
                        return true
                    }
                }
            }
        }
		return false
    }

    private func startAdvertising() {
        if advertisingInProgress {
            logger.log("Refresh advertising timer...")
            if let timer = adTimer {
                adTimer = nil
                timer.invalidate()
            }
        } else {
            logger.log("Advertising whisperer...")
        }
		factory.advertise(services: [BluetoothData.whisperServiceUuid], localName: BluetoothData.deviceId(conversation.id))
        advertisingInProgress = true
        let interval = max(listenerAdTime, whispererAdTime)
        adTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            // run loop will invalidate the timer
            self.adTimer = nil
            self.stopAdvertising()
        }
    }
    
    private func stopAdvertising() {
        guard advertisingInProgress else {
            // nothing to do
            return
        }
        logger.log("Stop advertising whisperer")
        factory.stopAdvertising()
        advertisingInProgress = false
        if let timer = adTimer {
            // global cancellation: invalidate the running timer
            adTimer = nil
            timer.invalidate()
        }
		// forget the peripherals which started the advertising,
		// in case they need to rejoin later on.
		advertisers.removeAll()
    }
    
	@discardableResult private func ensureRemote(_ central: CBCentral) -> Remote {
        if let remote = remotes[central] {
            // we've already connected this listener
            return remote
        }
		logger.log("Central \(central) is connecting to the control channel")
		let remote = Remote(central: central)
        remotes[central] = remote
        return remote
    }

	private func removeRemote(_ remote: Remote) {
		remotes.removeValue(forKey: remote.central)
		removedRemotes[remote.central] = remote
		if !remote.hasDropped {
			// tell this remote we're dropping it
			let chunk = WhisperProtocol.ProtocolChunk.dropping()
			if !factory.updateValue(value: chunk.toData(),
									characteristic: BluetoothData.controlOutCharacteristic,
									central: remote.central) {
				logger.error("Drop message for remote \(remote.id) failed to central: \(remote.central)")
			}
			if let index = listeners.firstIndex(of: remote.central) {
				listeners.remove(at: index)
				eavesdroppers.append(remote.central)
			}
		}
	}

    private func leaveConversation() {
		// tell everyone we are leaving the conversation
		logger.info("Sending leaving conversation message to all remotes")
		let chunk = WhisperProtocol.ProtocolChunk.dropping()
		if !factory.updateValue(value: chunk.toData(),
								characteristic: BluetoothData.controlOutCharacteristic) {
			logger.error("Leaving conversation message failed to send to all remotes")
		}
		// move all the remotes to removedRemotes
		for remote in remotes.values {
			removedRemotes[remote.central] = remote
		}
		remotes.removeAll()
    }
}
