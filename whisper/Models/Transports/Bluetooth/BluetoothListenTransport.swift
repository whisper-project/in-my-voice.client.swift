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
    
    var addRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var dropRemoteSubject: PassthroughSubject<Remote, Never> = .init()
	var contentSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()
	var controlSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> = .init()

    func start(failureCallback: @escaping (String) -> Void) {
        startDiscovery()
    }
    
    func stop() {
        stopDiscovery()
        if let publisher = self.publisher {
            drop(remote: publisher)
        } else {
            for remote in remotes.values {
                drop(remote: remote)
            }
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
    
    func sendControl(remote: Remote, chunks: [WhisperProtocol.ProtocolChunk]) {
        guard chunks.count == 1, chunks[0].isReplayRequest() else {
            fatalError("Bluetooth listeners can only send a single replay request packet, nothing else")
        }
        remote.peripheral.readValue(for: remote.contentOutChannel!)
    }
    
    func drop(remote: Remote) {
        if remote === publisher {
            logger.log("Dropping publisher remote \(remote.id)")
			publisher = nil
			if let c = remote.conversation, let chan = remote.controlInChannel, conversation == c {
				let chunk = WhisperProtocol.ProtocolChunk.dropping(c: c)
				remote.peripheral.writeValue(chunk.toData(), for: chan, type: .withoutResponse)
			} else {
				logger.error("Failed to notify publisher we are dropping")
			}
        } else {
            guard remotes.removeValue(forKey: remote.peripheral) != nil else {
                logger.error("Ignoring request to drop unknown remote \(remote.id)")
                return
            }
            logger.log("Dropping unused remote \(remote.id)")
        }
        disconnectsInProgress[remote.peripheral] = remote
		factory.disconnect(remote.peripheral)
		dropRemoteSubject.send(remote)
    }
    
    func subscribe(remote: Remote) {
        guard publisher == nil else {
            fatalError("Can't subscribe to \(remote.id) when already subscribed to \(publisher!)")
        }
		guard let selected = remotes.removeValue(forKey: remote.peripheral),
			  selected.authorized,
			  let c = selected.conversation,
			  let controlIn = selected.controlInChannel,
			  let contentOut = selected.contentOutChannel
		else {
            fatalError("Received request to subscribe to \(remote.id) but we're not authorized to subscribe")
        }
		guard conversation == nil || conversation == c else {
			fatalError("Subscribing to the wrong conversation? (actual: \(c), desired: \(String(describing: conversation))")
		}
        logger.log("Subscribing to remote \(remote.id) with name \(remote.name)")
        publisher = selected
        // subscribing implicitly stops discovery
        stopDiscovery()
        // complete the content subscription
		conversation = c
		selected.peripheral.setNotifyValue(true, for: contentOut)
		let chunk = WhisperProtocol.ProtocolChunk.joining(c: c)
		selected.peripheral.writeValue(chunk.toData(), for: controlIn, type: .withoutResponse)
        // drop the other remotes
        for remote in remotes.values {
			drop(remote: remote)
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
        if let uuids = pair.1[CBAdvertisementDataServiceUUIDsKey] as? Array<CBUUID> {
            if uuids.contains(BluetoothData.whisperServiceUuid) {
                guard let adName = pair.1[CBAdvertisementDataLocalNameKey],
                      let id = adName as? String else {
                    logger.error("Ignoring advertisement with no device id")
                    return
                }
                guard remotes[pair.0] == nil else {
//                    logger.debug("Ignoring repeat ad from remote \(id)")
                    return
                }
                logger.log("Connecting to remote \(id): \(pair.0)")
                remotes[pair.0] = Whisperer(peripheral: pair.0, id: id)
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
		logger.log("Connected to remote \(remote.id), readying...")
		remote.peripheral.discoverCharacteristics(
			[
				BluetoothData.contentOutUuid,
				BluetoothData.controlInUuid,
				BluetoothData.controlOutUuid,
			],
			for: whisperSvc
		)
    }
    
    private func disconnectedRemote(_ peripheral: CBPeripheral) {
        if let remote = disconnectsInProgress.removeValue(forKey: peripheral) {
            // this is an expected disconnect
            logger.info("Completed drop of remote \(remote.id) with name \(remote.name)")
        } else if peripheral == publisher?.peripheral {
            logger.log("Publisher \(self.publisher!.id) has stopped publishing")
            remotes.removeValue(forKey: peripheral)
            dropRemoteSubject.send(publisher!)
            publisher = nil
            // lost our whisperer, look again
            startDiscovery()
        } else if let remote = remotes.removeValue(forKey: peripheral) {
            logger.log("Remote \(remote.id) has stopped publishing")
            dropRemoteSubject.send(remote)
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
        guard service.characteristics != nil else {
            fatalError("Conected to a whisper service with no characteristics")
        }
        logger.log("Trying to pair with connected whisper service on: \(remote.id)...")
        let allCs = service.characteristics!
        if let controlOut = allCs.first(where: { $0.uuid == BluetoothData.controlOutUuid }) {
            remote.controlOutChannel = controlOut
        } else {
            fatalError("Whisper service has no control channel out characteristic")
        }
        if let controlIn = allCs.first(where: { $0.uuid == BluetoothData.controlInUuid }) {
            remote.controlInChannel = controlIn
        } else {
            fatalError("Whisper service has no control channel in characteristic")
        }
        if let contentOut = allCs.first(where: { $0.uuid == BluetoothData.contentOutUuid }) {
            remote.contentOutChannel = contentOut
        } else {
            fatalError("Whisper service has no content channel out characteristic")
        }
    }
    
    /// Get a confirmation or error from an attempt to write our name to a remote
    private func wroteValue(_ triple: (CBPeripheral, CBCharacteristic, Error?)) {
        guard let remote = remotes[triple.0] else {
            fatalError("Received write result for a non-remote: \(triple.0)")
        }
        guard triple.1.uuid == BluetoothData.controlInUuid else {
            fatalError("Received write result for unexpected characteristic: \(triple.1)")
        }
        if triple.2 != nil {
            logger.log("Pairing failed with remote \(remote.id): \(triple.2)")
            drop(remote: remote)
        } else {
            logger.log("Successfully sent name to \(remote.id)")
            remote.controlSubscribed = true
            maybeAddRemote(remote: remote)
        }
    }
    
    // got a confirmation of an attempt to subscribe
    private func subscribedValue(_ triple: (CBPeripheral, CBCharacteristic, Error?)) {
        guard triple.0 == publisher?.peripheral else {
            logger.error("Ignoring subscription result for non-publisher: \(triple.0)")
            return
        }
        guard triple.1.uuid == BluetoothData.contentOutUuid || triple.1.uuid == BluetoothData.contentOutUuid else {
            logger.error("Ignoring subscription result for unexpected characteristic: \(triple.1)")
            return
        }
        guard disconnectsInProgress[triple.0] == nil else {
            // ignore errors during disconnect
            return
        }
        guard triple.2 != nil else {
            // no action needed on success
            return
        }
        // if we failed to subscribe, we have to force-drop the publisher;
        // this will force the client to rediscover and re-subscribe
        logger.error("Failed to subscribe to the publisher")
        drop(remote: publisher!)
    }
    
    // receive an updated value either from a read or a publisher push
    private func readValue(_ triple: (CBPeripheral, CBCharacteristic, Error?)) {
        if triple.0 == publisher?.peripheral {
            if let error = triple.2 {
                logger.error("Got error on publisher read: \(error)")
                return
            } else if triple.1.uuid == publisher!.controlOutChannel!.uuid {
				if let textData = triple.1.value,
				   let chunk = WhisperProtocol.ProtocolChunk.fromData(textData) {
					controlSubject.send((remote: publisher!, chunk: chunk))
				} else {
					logger.error("Ignoring invalid control data received from publisher: \(String(describing: triple.1.value))")
				}
            } else if triple.1.uuid == publisher!.contentOutChannel!.uuid {
                if let textData = triple.1.value,
                   let chunk = WhisperProtocol.ProtocolChunk.fromData(textData) {
                    contentSubject.send((remote: publisher!, chunk: chunk))
                } else {
                    logger.error("Ignoring invalid content data received from publisher: \(String(describing: triple.1.value))")
                }
            } else {
                logger.error("Whisperer received value for an unexpected characteristic: \(triple.1)")
            }
        } else if let remote = remotes[triple.0] {
            if let error = triple.2 {
                logger.error("Read from remote \(remote.id) failed: \(error)")
                return
            } else if triple.1 == remote.controlInChannel! {
                logger.log("Read name value from remote \(remote.id)")
                if let nameData = triple.1.value, !nameData.isEmpty {
                    remote.contentSubscribed = true
                    remote.name = String(decoding: nameData, as: UTF8.self)
                    maybeAddRemote(remote: remote)
                } else {
                    logger.error("Read malformed name value from remote \(remote.id)")
                    drop(remote: remote)
                }
            } else {
                logger.error("Ignoring read value from remote \(remote.id) for an unexpected characteristic: \(triple.1)")
            }
        } else {
            logger.error("Ignoring read value from an unexpected source: \(triple.0)")
        }
    }
    
    // MARK: internal types, properties, and initialization
    class Whisperer: TransportRemote {
        var id: String
        var name: String = ""
		var authorized: Bool = false

        fileprivate var peripheral: CBPeripheral
		fileprivate var conversation: Conversation?
        fileprivate var controlOutChannel: CBCharacteristic?
        fileprivate var controlInChannel: CBCharacteristic?
        fileprivate var contentOutChannel: CBCharacteristic?
        fileprivate var controlSubscribed: Bool = false
        fileprivate var contentSubscribed: Bool = false
        
        fileprivate init(peripheral: CBPeripheral, id: String) {
            self.peripheral = peripheral
            self.id = id
        }
    }
    
    private var factory = BluetoothFactory.shared
    private var remotes: [CBPeripheral: Remote] = [:]
    private var publisher: Remote?
    private var cancellables: Set<AnyCancellable> = []
    private var isInBackground = false
    private var scanRefreshCount = 0
    private var disconnectsInProgress: [CBPeripheral: Remote] = [:]
	private var conversation: Conversation? = nil

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
        factory.scan(forServices: [BluetoothData.whisperServiceUuid], allow_repeats: true)
        startAdvertising()
    }
    
    private func stopDiscovery() {
        logger.log("Stop scanning for whisperers")
        stopAdvertising()
        factory.stopScan()
    }
    
    /// There are several race conditions on qualifying publishers;
    /// this is the gate that resolves them and notifies when appropriate.
    private func maybeAddRemote(remote: Remote) {
        guard remote.authorized else {
            // nothing to do
            return
        }
        addRemoteSubject.send(remote)
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
