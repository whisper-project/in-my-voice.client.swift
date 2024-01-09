// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine
import CoreBluetooth

final class BluetoothListenTransport: SubscribeTransport {
    // MARK: Protocol types, properties, and methods
    typealias Remote = Whisperer
    
    var lostRemoteSubject: PassthroughSubject<Remote, Never> = .init()
	var contentSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()
	var controlSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()

    func start(failureCallback: @escaping (String) -> Void) {
		self.failureCallback = failureCallback
        startDiscovery()
    }
    
    func stop() {
        stopDiscovery()
		for remote in Array(remotes.values) {
			drop(remote: remote)
		}
    }
    
    func goToBackground() {
        // can't do discovery in background
        stopDiscovery()
        isInBackground = true
    }
    
    func goToForeground() {
        isInBackground = false
        // resume discovery if necessary
        startDiscovery()
    }
    
    func sendControl(remote: Remote, chunk: WhisperProtocol.ProtocolChunk) {
		guard let channel = remote.controlInChannel else {
			fatalError("Missing control channel on remote: \(remote)")
		}
		remote.peripheral.writeValue(chunk.toData(), for: channel, type: .withResponse)
    }
    
    func drop(remote: Remote) {
		guard let existing = remotes.removeValue(forKey: remote.peripheral) else {
			logger.error("Ignoring request to drop unknown remote \(remote.id)")
			return
		}
		if let channel = remote.controlInChannel {
			logger.log("Explicitly dropping remote: \(existing.id)")
			let chunk = WhisperProtocol.ProtocolChunk.dropping()
			existing.peripheral.writeValue(chunk.toData(), for: channel, type: .withoutResponse)
        } else {
			logger.info("Implicitly dropping remote: \(existing.id)")
        }
		removeRemote(existing)
    }
    
	func subscribe(remote: Remote, conversation: Conversation) {
		guard let selected = remotes[remote.peripheral],
			  let contentOut = selected.contentOutChannel
		else {
            fatalError("Received request to subscribe to \(remote.id) which is not a valid remote")
        }
        logger.log("Subscribing to remote \(selected.id)")
		publisher = remote
        // subscribing implicitly stops discovery
        stopDiscovery()
        // complete the content subscription
		self.conversation = conversation
		selected.peripheral.setNotifyValue(true, for: contentOut)
        // drop the other remotes
        for remote in Array(remotes.values) {
			if remote !== publisher {
				drop(remote: remote)
			}
        }
    }
    
    // MARK: Central event handlers
    
    /// Called when we see an ad from a potential publisher
    private func discoveredRemote(_ pair: (CBPeripheral, [String: Any])) {
        guard publisher == nil else {
            // ignore advertisements seen once we're subscribed
            logger.warning("Received ad after subscription from \(pair.0)")
            return
        }
		guard !advertisers.contains(pair.0) else {
			// logger.debug("Ignoring repeat ads from existing advertiser")
			return
		}
		advertisers.append(pair.0)
        if let uuids = pair.1[CBAdvertisementDataServiceUUIDsKey] as? Array<CBUUID> {
            if uuids.contains(BluetoothData.whisperServiceUuid) {
                guard let adName = pair.1[CBAdvertisementDataLocalNameKey],
                      let id = adName as? String
				else {
					logger.error("Ignoring advertisement with no conversation id from: \(pair.0)")
                    return
                }
				guard conversation == nil || conversation!.id == id else {
					logger.info("Ignoring advertisement with non-matching conversation id from: \(pair.0)")
					return
				}
                logger.log("Connecting to remote \(pair.0)")
                remotes[pair.0] = Remote(peripheral: pair.0)
                factory.connect(pair.0)
                return
            }
        }
    }

	/// Called when we get a connection establlished to an advertised whisperer
	private func connectedRemote(_ peripheral: CBPeripheral) {
		guard remotes[peripheral] != nil else {
			fatalError("Connected to remote \(peripheral) but didn't request a connection")
		}
		logger.log("Found a peripheral, ensuring it's a whisperer")
		peripheral.discoverServices([BluetoothData.whisperServiceUuid])
	}

    /// Called when we get discovered a whisper service on a remote
    private func connectedService(_ pair: (CBPeripheral, [CBService])) {
        guard let remote = remotes[pair.0] else {
            fatalError("Discovered services for remote \(pair.0) which is not connected")
        }
		guard let whisperSvc = pair.1.first(where: {svc in svc.uuid == BluetoothData.whisperServiceUuid}) else {
			fatalError("Connected to advertised publisher \(remote) but it has no whisper service")
		}
		logger.log("Connected to whispering remote \(remote.id), getting characteristics...")
		remote.peripheral.discoverCharacteristics(
			[
				BluetoothData.contentOutUuid,
				BluetoothData.controlInUuid,
				BluetoothData.controlOutUuid,
			],
			for: whisperSvc
		)
    }
    
	/// Called when we have lost connection with a remote
    private func disconnectedRemote(_ peripheral: CBPeripheral) {
        if let remote = dropsInProgress.removeValue(forKey: peripheral) {
            // this is an expected disconnect
            logger.info("Completed disconnect from remote \(remote.id)")
        } else if let remote = remotes[peripheral] {
            logger.info("Remote \(remote.id) has disconnected unexpectedly")
			remote.contentOutChannel = nil
			remote.controlInChannel = nil
			remote.controlOutChannel = nil
			removeRemote(remote)
			lostRemoteSubject.send(remote)
        } else {
            logger.error("Ignoring disconnect from unknown peripheral: \(peripheral)")
        }
    }
    
    /// Called when we have discovered characteristics for the whisper service on a remote
    private func pairWithWhisperer(_ pair: (CBPeripheral, CBService)) {
        let (peripheral, service) = pair
        guard let remote = remotes[peripheral] else {
            fatalError("Connected to a whisper service that's not a remote")
        }
        guard let allCs = service.characteristics else {
            fatalError("Conected to a whisper service with no characteristics")
        }
        logger.log("Trying to pair with connected whisper service on: \(remote.peripheral)...")
        if let controlOut = allCs.first(where: { $0.uuid == BluetoothData.controlOutUuid }) {
            remote.controlOutChannel = controlOut
			peripheral.setNotifyValue(true, for: controlOut)
        } else {
            fatalError("Whisper service has no control channel out characteristic")
        }
        if let controlIn = allCs.first(where: { $0.uuid == BluetoothData.controlInUuid }) {
            remote.controlInChannel = controlIn
			// offer to listen so they know who we are
			logger.info("Sending listen offer to \(remote.id)")
			let chunk = WhisperProtocol.ProtocolChunk.listenOffer(conversation)
			sendControl(remote: remote, chunk: chunk)
        } else {
            fatalError("Whisper service has no control channel in characteristic")
        }
        if let contentOut = allCs.first(where: { $0.uuid == BluetoothData.contentOutUuid }) {
            remote.contentOutChannel = contentOut
			// don't subscribe to content out until we are authorized!
        } else {
            fatalError("Whisper service has no content channel out characteristic")
        }
    }
    
    /// Get a confirmation or error from an attempt to write to a remote
    private func wroteValue(_ triple: (CBPeripheral, CBCharacteristic, Error?)) {
        guard let remote = remotes[triple.0] else {
            fatalError("Received write result for a non-remote: \(triple.0)")
        }
        guard triple.1.uuid == BluetoothData.controlInUuid else {
            fatalError("Received write result for unexpected characteristic: \(triple.1)")
        }
		guard dropsInProgress[triple.0] == nil else {
			logger.log("Write result received during disconnect from \(remote.id), ignoring it")
			return
		}
        if triple.2 != nil {
            logger.error("Pairing failed with remote \(remote.id): \(triple.2)")
            //warn the client and fail
			PreferenceData.bluetoothErrorCount += 1
			failureCallback?("Communication failure while connecting to Whisperer")
		} else {
            logger.log("Successfully sent control packet to \(remote.id)")
        }
    }
    
    // got a confirmation of an attempt to subscribe
    private func subscribedValue(_ triple: (CBPeripheral, CBCharacteristic, Error?)) {
		guard let remote = remotes[triple.0] else {
            fatalError("Received subscription result for a non-remote: \(triple.0)")
        }
        guard triple.1.uuid == BluetoothData.controlOutUuid || triple.1.uuid == BluetoothData.contentOutUuid else {
            fatalError("Received subscription result for unexpected characteristic: \(triple.1)")
        }
        guard dropsInProgress[triple.0] == nil else {
			logger.log("Subscribe result received during disconnect from \(remote.id), ignoring it")
            return
        }
        guard triple.2 != nil else {
            // no action needed on success
            return
        }
        // if we failed to subscribe, we have to warn the client
		logger.error("Failed to subscribe to peripheral: \(remote.id), channel: \(triple.1.uuid)")
		PreferenceData.bluetoothErrorCount += 1
        failureCallback?("Communication failure while connecting to Whisperer")
    }
    
    // receive an updated value from a remote
    private func readValue(_ triple: (CBPeripheral, CBCharacteristic, Error?)) {
		if triple.1.uuid == BluetoothData.contentOutUuid {
			if let error = triple.2 {
				// got a content read failure, this must be from the publisher
				logger.error("Got error on content update: \(error)")
				PreferenceData.bluetoothErrorCount += 1
			} else if let remote = publisher,
					  let textData = triple.1.value,
					  let chunk = WhisperProtocol.ProtocolChunk.fromData(textData) {
				contentSubject.send((remote: remote, chunk: chunk))
			} else {
				logger.error("Ignoring invalid content data: \(String(describing: triple.1.value))")
				PreferenceData.bluetoothErrorCount += 1
			}
		} else if triple.1.uuid == BluetoothData.controlOutUuid {
			guard let remote = remotes[triple.0] else {
				fatalError("Received update from unknown peripheral: \(triple)")
			}
			if let error = triple.2 {
				// got a control read failure
				logger.error("Got error on control update from \(triple.0): \(error)")
				PreferenceData.bluetoothErrorCount += 1
				failureCallback?("Communication (read) failure while connecting to Whisperer")
			} else if let textData = triple.1.value,
					  let chunk = WhisperProtocol.ProtocolChunk.fromData(textData) {
				if let value = WhisperProtocol.ControlOffset(rawValue: chunk.offset),
				   case .dropping = value {
					logger.info("Advised of drop by \(remote.id)")
					removeRemote(remote)
					lostRemoteSubject.send(remote)
					return
				}
				controlSubject.send((remote: remote, chunk: chunk))
			} else {
				logger.error("Received invalid control data from remote \(remote.id): \(String(describing: triple.1.value))")
				PreferenceData.bluetoothErrorCount += 1
				failureCallback?("Communication (bad data) failure while connecting to Whisperer")
			}
		} else {
			fatalError("Got update of an unknown characteristic: \(String(describing: triple))")
		}
    }
    
    // MARK: internal types, properties, and initialization
    class Whisperer: TransportRemote {
        let id: String
		let kind: TransportKind = .local

        fileprivate var peripheral: CBPeripheral
        fileprivate var controlOutChannel: CBCharacteristic?
        fileprivate var controlInChannel: CBCharacteristic?
        fileprivate var contentOutChannel: CBCharacteristic?

        fileprivate init(peripheral: CBPeripheral) {
            self.peripheral = peripheral
			self.id = peripheral.identifier.uuidString
        }
    }
    
    private var factory = BluetoothFactory.shared
	private var advertisers: [CBPeripheral] = []
    private var remotes: [CBPeripheral: Remote] = [:]
	private var dropsInProgress: [CBPeripheral: Remote] = [:]
	private var publisher: Remote?
    private var cancellables: Set<AnyCancellable> = []
    private var isInBackground = false
    private var scanRefreshCount = 0
	private var conversation: Conversation? = nil
	private var failureCallback: ((String) -> Void)?

	init(_ c: Conversation?) {
        logger.log("Initializing Bluetooth whisper transport")
		self.conversation = c
        factory.advertisementSubject
            .sink{ [weak self] in self?.discoveredRemote($0) }
            .store(in: &cancellables)
        factory.servicesSubject
            .sink{ [weak self] in self?.connectedService($0) }
            .store(in: &cancellables)
        factory.characteristicsSubject
            .sink{ [weak self] in self?.pairWithWhisperer($0) }
            .store(in: &cancellables)
        factory.receivedValueSubject
            .sink{ [weak self] in self?.readValue($0) }
            .store(in: &cancellables)
        factory.writeResultSubject
            .sink{ [weak self] in self?.wroteValue($0) }
            .store(in: &cancellables)
        factory.notifyResultSubject
            .sink{ [weak self] in self?.subscribedValue($0) }
            .store(in: &cancellables)
		factory.connectedSubject
			.sink{ [weak self] in self?.connectedRemote($0) }
			.store(in: &cancellables)
        factory.disconnectedSubject
            .sink{ [weak self] in self?.disconnectedRemote($0) }
            .store(in: &cancellables)
    }
    
    deinit {
        logger.log("Destroying Bluetooth whisper transport")
        cancellables.cancel()
    }
    
    //MARK: internal methods
	private func removeRemote(_ remote: Remote) {
		remotes.removeValue(forKey: remote.peripheral)
		dropsInProgress[remote.peripheral] = remote
		if let channel = remote.contentOutChannel {
			remote.peripheral.setNotifyValue(false, for: channel)
		}
		if let channel = remote.contentOutChannel {
			remote.peripheral.setNotifyValue(false, for: channel)
		}
		factory.disconnect(remote.peripheral)
		if remote === publisher {
			publisher = nil
			startDiscovery()
		}
	}
	
    private func startDiscovery() {
        guard !isInBackground else {
            // can't do discovery in the background
            return
        }
        guard publisher == nil else {
            // we don't discover if we have a publisher
            return
        }
        logger.log("Start scanning for whisperers")
		advertisers = []
        factory.scan(forServices: [BluetoothData.whisperServiceUuid], allow_repeats: true)
        startAdvertising()
    }
    
    private func stopDiscovery() {
        logger.log("Stop scanning for whisperers")
        stopAdvertising()
        factory.stopScan()
    }

    private func startAdvertising() {
        logger.log("Start advertising listener")
        Timer.scheduledTimer(withTimeInterval: listenerAdTime, repeats: false) { _ in
            self.stopAdvertising()
        }
		if let c = conversation {
			factory.advertise(services: [BluetoothData.listenServiceUuid], localName: BluetoothData.deviceId(c.id))
		} else {
			factory.advertise(services: [BluetoothData.listenServiceUuid], localName: "discover")
		}
    }
    
    private func stopAdvertising() {
        logger.log("Stop advertising listener")
        factory.stopAdvertising()
    }
}
