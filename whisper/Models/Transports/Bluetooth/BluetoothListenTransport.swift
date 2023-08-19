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
    var receivedChunkSubject: PassthroughSubject<(remote: Remote, chunk: TextProtocol.ProtocolChunk), Never> = .init()
    
    func start() -> TransportDiscovery {
        return startDiscovery()
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
    
    func startDiscovery() -> TransportDiscovery {
        logger.log("Start scanning for whisperers")
        factory.scan(forServices: [WhisperData.whisperServiceUuid], allow_repeats: true)
        startAdvertising()
        return .automatic
    }
    
    func stopDiscovery() {
        logger.log("Stop scanning for whisperers")
        stopAdvertising()
        factory.stopScan()
    }
    
    func goToBackground() {
        // can't do discovery in background
        stopDiscovery()
    }
    
    func goToForeground() {
    }
    
    func send(remote: Remote, chunks: [TextProtocol.ProtocolChunk]) {
        guard chunks.count == 1, chunks[0].isReplayRequest() else {
            fatalError("Bluetooth listeners can only send a single replay request packet, nothing else")
        }
        remote.peripheral.readValue(for: remote.textCharacteristic!)
    }
    
    func drop(remote: Remote) {
        if remote === publisher {
            logger.log("Dropping publisher remote \(remote.id)")
            publisher = nil
        } else {
            guard remotes.removeValue(forKey: remote.peripheral) != nil else {
                logger.error("Ignoring request to drop unknown remote \(remote.id)")
                return
            }
            logger.log("Dropping unused remote \(remote.id)")
        }
        disconnectsInProgress[remote.peripheral] = remote
        if remote.canBePublisher() {
            // we have paired with this remote, warn it we are dropping it
            remote.peripheral.readValue(for: remote.rejectCharacteristic!)
            // give a little time for the message to reach it, then disconnect
            Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { _ in
                self.factory.disconnect(remote.peripheral)
            }
            // tell the client we are dropping this remote
            dropRemoteSubject.send(remote)
        } else {
            // we have not established communication with this remote, so just drop it
            factory.disconnect(remote.peripheral)
        }
    }
    
    func subscribe(remote: Whisperer) {
        guard publisher == nil else {
            fatalError("Can't subscribe to \(remote.id) when already subscribed to \(publisher!)")
        }
        guard let selected = remotes[remote.peripheral], selected.canBePublisher() else {
            fatalError("Received request to subscribe to \(remote.id) but it's not qualified to be a publisher")
        }
        logger.log("Subscribing to remote \(remote.id) with name \(remote.name)")
        publisher = selected
        // subscribing implicitly stops discovery
        stopDiscovery()
        // complete the Bluetooth subscription
        selected.peripheral.setNotifyValue(true, for: selected.textCharacteristic!)
        selected.peripheral.setNotifyValue(true, for: selected.rejectCharacteristic!)
        // drop the other remotes
        for remote in remotes.values {
            if remote === selected {
                continue
            }
            logger.log("Dropping unused remote \(remote.id) (\(remote.name))")
            remote.peripheral.readValue(for: remote.rejectCharacteristic!)
            dropRemoteSubject.send(remote)
        }
        remotes.removeAll()
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
            if uuids.contains(WhisperData.whisperServiceUuid) {
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
    
    /// Called when we get a connection established to a potential publisher
    private func connectedRemote(_ pair: (CBPeripheral, [CBService])) {
        guard let remote = remotes[pair.0] else {
            fatalError("Connected to remote \(pair.0) but didn't request a connection")
        }
        if let whisperSvc = pair.1.first(where: {svc in svc.uuid == WhisperData.whisperServiceUuid}) {
            logger.log("Connected to remote \(remote.id), readying...")
            remote.peripheral.discoverCharacteristics(
                [
                    WhisperData.listenNameUuid,
                    WhisperData.whisperNameUuid,
                    WhisperData.textUuid,
                    WhisperData.disconnectUuid,
                ],
                for: whisperSvc
            )
        } else {
            fatalError("Connected to advertised publisher \(remote) but it has no whisper service")
        }
    }
    
    private func disconnectedRemote(_ peripheral: CBPeripheral) {
        if let remote = disconnectsInProgress.removeValue(forKey: peripheral) {
            // this is an expected disconnect
            logger.info("Completed drop of remote \(remote.id) with name \(remote.name)")
        } else if peripheral == publisher?.peripheral {
            logger.log("Publisher \(self.publisher!.id) has stopped publishing")
            drop(remote: publisher!)
        } else if let remote = remotes[peripheral] {
            logger.log("Remote \(remote.id) has stopped publishing")
            drop(remote: remote)
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
        if let listenNameC = allCs.first(where: { $0.uuid == WhisperData.listenNameUuid }) {
            remote.listenNameCharacteristic = listenNameC
        } else {
            fatalError("Whisper service has no listener name characteristic")
        }
        if let whisperNameC = allCs.first(where: { $0.uuid == WhisperData.whisperNameUuid }) {
            remote.whisperNameCharacteristic = whisperNameC
        } else {
            fatalError("Whisper service has no publisher name characteristic")
        }
        if let liveTextC = allCs.first(where: { $0.uuid == WhisperData.textUuid }) {
            remote.textCharacteristic = liveTextC
        } else {
            fatalError("Whisper service has no text protocol characteristic")
        }
        if let disconnectC = allCs.first(where: { $0.uuid == WhisperData.disconnectUuid }) {
            remote.rejectCharacteristic = disconnectC
        } else {
            fatalError("Whisper service has no disconnect characteristic")
        }
        let idAndName = "\(WhisperData.deviceId)|\(WhisperData.userName())"
        peripheral.writeValue(Data(idAndName.utf8), for: remote.listenNameCharacteristic!, type: .withResponse)
        peripheral.readValue(for: remote.whisperNameCharacteristic!)
    }
    
    /// Get a confirmation or error from an attempt to write our name to a remote
    private func wroteValue(_ triple: (CBPeripheral, CBCharacteristic, Error?)) {
        guard let remote = remotes[triple.0] else {
            fatalError("Received write result for a non-remote: \(triple.0)")
        }
        guard triple.1.uuid == WhisperData.listenNameUuid else {
            fatalError("Received write result for unexpected characteristic: \(triple.1)")
        }
        if triple.2 != nil {
            logger.log("Pairing failed with remote \(remote.id): \(triple.2)")
            drop(remote: remote)
        } else {
            logger.log("Successfully sent name to \(remote.id)")
            remote.sentName = true
            maybeAddRemote(remote: remote)
        }
    }
    
    // got a confirmation of an attempt to subscribe
    private func subscribedValue(_ triple: (CBPeripheral, CBCharacteristic, Error?)) {
        guard triple.0 == publisher?.peripheral else {
            logger.error("Ignoring subscription result for non-publisher: \(triple.0)")
            return
        }
        guard triple.1.uuid == WhisperData.textUuid || triple.1.uuid == WhisperData.disconnectUuid else {
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
        if let disconnected = disconnectsInProgress[triple.0] {
            if triple.1.uuid == disconnected.rejectCharacteristic!.uuid {
                logger.log("Remote \(disconnected.id) acknowledged drop request")
            } else {
                logger.log("Ignoring read from disconnected remote \(disconnected.id)")
            }
            return
        }
        if triple.0 == publisher?.peripheral {
            if let error = triple.2 {
                logger.error("Got error on publisher read: \(error)")
                drop(remote: publisher!)
            } else if triple.1.uuid == publisher!.rejectCharacteristic!.uuid {
                logger.log("Publisher rejected this subscriber")
                drop(remote: publisher!)
            } else if triple.1.uuid == publisher!.textCharacteristic!.uuid {
                if let textData = triple.1.value,
                   let chunk = TextProtocol.ProtocolChunk.fromData(textData) {
                    receivedChunkSubject.send((remote: publisher!, chunk: chunk))
                } else {
                    logger.error("Ignoring non-text-protocol data received from publisher: \(String(describing: triple.1.value))")
                }
            } else {
                logger.error("Whisperer received value for an unexpected characteristic: \(triple.1)")
            }
        } else if let remote = remotes[triple.0] {
            if let error = triple.2 {
                logger.error("Read from remote \(remote.id) failed: \(error)")
                drop(remote: remote)
            } else if triple.1 == remote.whisperNameCharacteristic! {
                logger.log("Read name value from remote \(remote.id)")
                if let nameData = triple.1.value, !nameData.isEmpty {
                    remote.haveName = true
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
    
    // MARK: internal types, properties, and methods

    class Whisperer: TransportRemote {
        var id: String
        var name: String = ""
        
        fileprivate var peripheral: CBPeripheral
        fileprivate var listenNameCharacteristic: CBCharacteristic?
        fileprivate var whisperNameCharacteristic: CBCharacteristic?
        fileprivate var textCharacteristic: CBCharacteristic?
        fileprivate var rejectCharacteristic: CBCharacteristic?
        fileprivate var sentName: Bool = false
        fileprivate var haveName: Bool = false
        
        fileprivate init(peripheral: CBPeripheral, id: String) {
            self.peripheral = peripheral
            self.id = id
        }
        
        fileprivate func canBePublisher() -> Bool {
            return self.sentName && self.haveName
        }
    }
    
    private var factory = BluetoothFactory.shared
    private var remotes: [CBPeripheral: Whisperer] = [:]
    private var publisher: Remote?
    private var cancellables: Set<AnyCancellable> = []
    private var scanRefreshCount = 0
    private var disconnectsInProgress: [CBPeripheral: Remote] = [:]
    
    init() {
        logger.log("Initializing Bluetooth whisper transport")
        factory.advertisementSubject
            .sink{ [weak self] in self?.discoveredRemote($0) }
            .store(in: &cancellables)
        factory.servicesSubject
            .sink{ [weak self] in self?.connectedRemote($0) }
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
        factory.disconnectedSubject
            .sink{ [weak self] in self?.disconnectedRemote($0) }
            .store(in: &cancellables)
    }
    
    deinit {
        logger.log("Destroying Bluetooth whisper transport")
        cancellables.cancel()
    }

    /// There are several race conditions on qualifying publishers;
    /// this is the gate that resolves them and notifies when appropriate.
    private func maybeAddRemote(remote: Remote) {
        guard remote.canBePublisher() else {
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
        factory.advertise(services: [WhisperData.listenServiceUuid])
    }
    
    private func stopAdvertising() {
        logger.log("Stop advertising listener")
        factory.stopAdvertising()
    }
}
