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
		logger.info("Starting Bluetooth listen transport")
		registerCallbacks()
		running = true
		self.failureCallback = failureCallback
        startDiscovery()
    }
    
    func stop() {
		logger.info("Stopping Bluetooth listen transport")
		running = false
        stopDiscovery()
		for remote in Array(remotes.values) {
			drop(remote: remote)
		}
		// the callbacks will unregister automatically
		// when the last connected whisperer disconnects
		// but we time limit how long this can happen
		DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: unregisterCallbacks)
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
		guard running else { return }
		guard let channel = remote.controlInChannel else {
			fatalError("Missing control channel on remote: \(remote)")
		}
		logger.info("Sending control packet to \(remote.kind) remote: \(remote.id): \(chunk)")
		remote.peripheral.writeValue(chunk.toData(), for: channel, type: .withResponse)
    }
    
    func drop(remote: Remote) {
		guard let existing = remotes[remote.peripheral] else {
			logger.error("Ignoring request to drop unknown \(remote.kind, privacy: .public) remote \(remote.id, privacy: .public)")
			return
		}
		removeRemote(existing, sendDrop: true)
    }
    
	func subscribe(remote: Remote, conversation: ListenConversation) {
		guard running else { return }
		if publisher === remote {
			logger.error("Ignoring duplicate subscribe to same publisher")
			return
		} else if publisher != nil {
			fatalError("Got subscribe request to \(remote.id) but already have publisher \(publisher!.id)")
		}
		guard let selected = remotes[remote.peripheral],
			  let contentOut = selected.contentOutChannel
		else {
            fatalError("Received request to subscribe to \(remote.id) which is not a valid remote")
        }
        logger.log("Subscribing to \(remote.kind) remote \(selected.id)")
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
		guard running else { return }
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
					logger.error("Ignoring advertisement with no conversation id from: \(pair.0, privacy: .public)")
                    return
                }
				guard BluetoothData.deviceId(conversation.id) == id else {
					logger.info("Ignoring advertisement with non-matching conversation id from: \(pair.0)")
					return
				}
                logger.log("Connecting to local remote \(pair.0)")
                remotes[pair.0] = Remote(peripheral: pair.0)
                factory.connect(pair.0)
                return
            }
        }
    }

	/// Called when we get a connection establlished to an advertised whisperer
	private func connectedRemote(_ peripheral: CBPeripheral) {
		guard running else { return }
		if remotes[peripheral] == nil {
			logger.info("Connected to local remote \(peripheral) but didn't request a connection")
			remotes[peripheral] = Remote(peripheral: peripheral)
		}
		logger.log("Found a peripheral, ensuring it's a whisperer")
		peripheral.discoverServices([BluetoothData.whisperServiceUuid])
	}

    /// Called when we get discovered a whisper service on a remote
    private func connectedService(_ pair: (CBPeripheral, [CBService])) {
		guard running else { return }
		let remote = remotes[pair.0] ?? {
			logger.info("Found services for local remote \(pair.0) but didn't discover them")
			let remote = Remote(peripheral: pair.0)
			remotes[pair.0] = remote
			return remote
		}()
		guard let whisperSvc = pair.1.first(where: {svc in svc.uuid == BluetoothData.whisperServiceUuid}) else {
			fatalError("Connected to \(remote) but it has no whisper service")
		}
		logger.log("Connected to whispering \(remote.kind) remote \(remote.id), getting characteristics...")
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
		guard let remote = remotes[peripheral] else {
			logger.error("Ignoring disconnect from unknown peripheral: \(peripheral, privacy: .public)")
			return
		}
		if remote.dropInProgress {
            // this is an expected disconnect
            logger.info("Completed disconnect from \(remote.kind) remote \(remote.id)")
			remotes.removeValue(forKey: peripheral)
			// if this was the publisher, look for a new one
			if remote === publisher {
				publisher = nil
				startDiscovery()
			}
        } else  {
            logger.info("\(remote.kind) Remote \(remote.id) has disconnected unexpectedly")
			remote.contentOutChannel = nil
			remote.controlInChannel = nil
			remote.controlOutChannel = nil
			remotes.removeValue(forKey: peripheral)
			lostRemoteSubject.send(remote)
        }
		if !running {
			if remotes.isEmpty {
				logger.info("Shutting down Bluetooth listen transport after disconnecting all remotes")
				unregisterCallbacks()
			} else {
				logger.log("Waiting to disconnect from \(self.remotes.count) remotes")
			}
		}
    }
    
    /// Called when we have discovered characteristics for the whisper service on a remote
    private func pairWithWhisperer(_ pair: (CBPeripheral, CBService)) {
		guard running else { return }
        let (peripheral, service) = pair
        guard let remote = remotes[peripheral] else {
            fatalError("Connected to a whisper service that's not a remote")
        }
        guard let allCs = service.characteristics else {
            fatalError("Conected to a whisper service with no characteristics")
        }
        logger.log("Trying to pair with connected whisper service on \(remote.peripheral)...")
        if let controlOut = allCs.first(where: { $0.uuid == BluetoothData.controlOutUuid }) {
            remote.controlOutChannel = controlOut
			peripheral.setNotifyValue(true, for: controlOut)
        } else {
            fatalError("Whisper service has no control channel out characteristic")
        }
        if let controlIn = allCs.first(where: { $0.uuid == BluetoothData.controlInUuid }) {
            remote.controlInChannel = controlIn
			// offer to listen so they know who we are
			logger.info("Sending listen offer to \(remote.kind) remote \(remote.id)")
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
		if remote.dropInProgress {
			logger.warning("Received a write result from a \(remote.kind) remote we are dropping: \(remote.id)")
			return
		}
        if triple.2 != nil {
            logger.error("Send of control packet failed to \(remote.kind, privacy: .public) remote \(remote.id, privacy: .public): \(triple.2, privacy: .public)")
			PreferenceData.bluetoothErrorCount += 1
			failureCallback?("Communication failure while connecting to Whisperer")
		} else {
            // logger.log("Successfully sent control packet to \(remote.kind) remote \(remote.id)")
        }
    }
    
    // got a confirmation of an attempt to subscribe or unsubscribe
    private func subscribedValue(_ triple: (CBPeripheral, CBCharacteristic, Error?)) {
		guard let remote = remotes[triple.0] else {
			fatalError("Received subscription result for a non-remote: \(triple.0)")
		}
		guard triple.1.uuid == BluetoothData.controlOutUuid || triple.1.uuid == BluetoothData.contentOutUuid else {
			fatalError("Received subscription result for unexpected characteristic: \(triple.1)")
		}
		if remote.dropInProgress {
			remote.pendingNotifyCount -= 1
			if triple.2 != nil {
				logger.warning("Failed to turn off notifications during drop of \(remote.kind) remote \(remote.id)")
				PreferenceData.bluetoothErrorCount += 1
			}
			if remote.pendingNotifyCount == 0 {
				logger.info("Disconnecting after notifications completed to dropped \(remote.kind) remote: \(remote.id)")
				factory.disconnect(triple.0)
			}
		} else if triple.2 != nil {
			// if we failed to subscribe, we have to warn the client
			logger.error("Failed to subscribe to peripheral: \(remote.id, privacy: .public), channel: \(triple.1.uuid, privacy: .public), error: \(triple.2, privacy: .public)")
			PreferenceData.bluetoothErrorCount += 1
			failureCallback?("Bluetooth subscription error while connecting")
        }
    }
    
    // receive an updated value from a remote
    private func readValue(_ triple: (CBPeripheral, CBCharacteristic, Error?)) {
		guard running else { return }
		if triple.1.uuid == BluetoothData.contentOutUuid {
			if let error = triple.2 {
				// got a content read failure, this must be from the publisher
				logger.error("Got error on content update: \(error, privacy: .public)")
				PreferenceData.bluetoothErrorCount += 1
			} else if let remote = publisher,
					  let textData = triple.1.value,
					  let chunk = WhisperProtocol.ProtocolChunk.fromData(textData) {
				contentSubject.send((remote: remote, chunk: chunk))
			} else {
				logger.error("Ignoring invalid content data: \(String(describing: triple.1.value), privacy: .public)")
				PreferenceData.bluetoothErrorCount += 1
			}
		} else if triple.1.uuid == BluetoothData.controlOutUuid {
			guard let remote = remotes[triple.0] else {
				fatalError("Received update from unknown peripheral: \(triple)")
			}
			if let error = triple.2 {
				// got a control read failure
				logger.error("Got error on control update from \(triple.0, privacy: .public): \(error, privacy: .public)")
				PreferenceData.bluetoothErrorCount += 1
				failureCallback?("Bluetooth read failure while connecting")
			} else if let textData = triple.1.value,
					  let chunk = WhisperProtocol.ProtocolChunk.fromData(textData) {
				if let value = WhisperProtocol.ControlOffset(rawValue: chunk.offset),
				   case .dropping = value {
					logger.notice("Advised of drop by \(remote.kind, privacy: .public) remote \(remote.id, privacy: .public)")
					removeRemote(remote)
					lostRemoteSubject.send(remote)
					return
				}
				logger.notice("Received control packet from \(remote.kind, privacy: .public) remote \(remote.id, privacy: .public): \(chunk, privacy: .public)")
				controlSubject.send((remote: remote, chunk: chunk))
			} else {
				logger.error("Received invalid control data from \(remote.kind, privacy: .public) remote \(remote.id, privacy: .public): \(String(describing: triple.1.value), privacy: .public)")
				PreferenceData.bluetoothErrorCount += 1
				failureCallback?("Bluetooth read data consistency failure while connecting")
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
		fileprivate var pendingNotifyCount: Int = 0
		fileprivate var dropInProgress: Bool = false

        fileprivate init(peripheral: CBPeripheral) {
            self.peripheral = peripheral
			self.id = peripheral.identifier.uuidString
        }
    }
    
	private var running = false
    private var factory = BluetoothFactory.shared
	private var advertisers: [CBPeripheral] = []
    private var remotes: [CBPeripheral: Remote] = [:]
	private var publisher: Remote?
    private var cancellables: Set<AnyCancellable> = []
    private var isInBackground = false
    private var scanRefreshCount = 0
	private var conversation: ListenConversation
	private var failureCallback: ((String) -> Void)?

	init(_ c: ListenConversation) {
        logger.log("Initializing Bluetooth listen transport")
		self.conversation = c
    }
    
    deinit {
        logger.log("Destroying Bluetooth whisper transport")
        unregisterCallbacks()
    }
    
    //MARK: internal methods
	private func removeRemote(_ remote: Remote, sendDrop: Bool = false) {
		guard !remote.dropInProgress else {
			// nothing to do
			return
		}
		remote.dropInProgress = true
		if sendDrop {
			if let channel = remote.controlInChannel {
				logger.log("Explicitly dropping \(remote.kind) remote: \(remote.id)")
				let chunk = WhisperProtocol.ProtocolChunk.dropping()
				remote.peripheral.writeValue(chunk.toData(), for: channel, type: .withoutResponse)
			} else {
				logger.error("Can't send drop packet to \(remote.kind, privacy: .public) remote: \(remote.id, privacy: .public)")
			}
		}
		if let channel = remote.contentOutChannel {
			remote.pendingNotifyCount += 1
			remote.peripheral.setNotifyValue(false, for: channel)
		}
		if let channel = remote.controlOutChannel {
			remote.pendingNotifyCount += 1
			remote.peripheral.setNotifyValue(false, for: channel)
		}
		// disconnect won't happen until we finish notifications
	}
	
    private func startDiscovery() {
		guard running else { return }
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
		factory.advertise(services: [BluetoothData.listenServiceUuid], localName: BluetoothData.deviceId(conversation.id))
    }
    
    private func stopAdvertising() {
        logger.log("Stop advertising listener")
        factory.stopAdvertising()
    }

	private func registerCallbacks() {
		logger.info("Registering Bluetooth callbacks")
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

	private func unregisterCallbacks() {
		logger.info("Unregistering Bluetooth callbacks")
		cancellables.cancel()
		cancellables.removeAll()
		if !remotes.isEmpty {
			logger.warning("Force disconnecting \(self.remotes.count) remotes")
			for remote in Array(remotes.values) {
				remotes.removeValue(forKey: remote.peripheral)
				factory.disconnect(remote.peripheral)
			}
		}
	}
}
