// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Combine
import CoreBluetooth

final class BluetoothWhisperTransport: PublishTransport {
    // MARK: Protocol properties and methods
    
    typealias Remote = Subscriber
    
    var addRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var dropRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var receivedChunkSubject: PassthroughSubject<(remote: Remote, chunk: TextProtocol.ProtocolChunk), Never> = .init()
    
    func start() -> TransportDiscovery {
        logger.log("Starting Bluetooth whisper transport...")
        whisperService = BluetoothData.whisperService()
        factory.publish(service: whisperService!)
        return startDiscovery()
    }
    
    func stop() {
        logger.log("Stopping Bluetooth whisper transport...")
        stopDiscovery()
        removeAllListeners()
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
        stopAdvertising()
    }
    
    func goToForeground() {
        guard isInBackground else {
            return
        }
        isInBackground = false
    }
    
    func startDiscovery() -> TransportDiscovery {
        factory.scan(forServices: [BluetoothData.listenServiceUuid], allow_repeats: true)
        startAdvertising()
        return .automatic
    }
    
    func stopDiscovery() {
        stopAdvertising()
        factory.stopScan()
    }
    
    func send(remote: Remote, chunks: [TextProtocol.ProtocolChunk]) {
        if var existing = directedChunks[remote.central] {
            existing.append(contentsOf: chunks)
        } else {
            directedChunks[remote.central] = chunks
        }
        updateListeners()
    }
    
    func drop(remote: Remote) {
        guard let removed = remotes.removeValue(forKey: remote.central) else {
            logger.log("Ignoring drop request for non-listener with id: \(remote.id)")
            return
        }
        logger.notice("Dropping listener \(removed.id) (\(removed.name)): \(removed.central)")
        // remember not to re-add this remote
        droppedRemotes.append(removed.id)
        // tell this remote we've dropped it
        if !factory.updateValue(value: Data(), characteristic: BluetoothData.whisperDisconnectCharacteristic, central: removed.central) {
            logger.error("Drop message for remote \(removed.id) failed to central: \(removed.central)")
        }
        dropRemoteSubject.send(removed)
    }
    
    func publish(chunks: [TextProtocol.ProtocolChunk]) {
        for chunk in chunks {
            pendingChunks.append(chunk)
        }
        updateListeners()
    }
    
    // MARK: Peripheral Event Handlers
    
    private func noticeAd(_ pair: (CBPeripheral, [String: Any])) {
        if let uuids = pair.1[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            if uuids.contains(BluetoothData.listenServiceUuid) {
                if let _ = advertisers[pair.0] {
//                    logger.debug("Ignored multiple repeat ads from already-pending listener \(_)")
                } else {
                    guard let adName = pair.1[CBAdvertisementDataLocalNameKey],
                          let id = adName as? String
                    else {
                        logger.error("Ignoring advertisement with no listener id from \(pair.0)")
                        return
                    }
                    guard !droppedRemotes.contains(id) else {
                        logger.info("Ignoring advertisement from dropped listener \(id)")
                        return
                    }
                    advertisers[pair.0] = id
                    logger.debug("Got first ad from listener \(id): \(pair.0)")
                    startAdvertising()
                }
            }
        }
    }
    
    private func noticeSubscription(_ pair: (CBCentral, CBCharacteristic)) {
        guard pair.1.uuid == BluetoothData.textUuid || pair.1.uuid == BluetoothData.disconnectUuid else {
            logger.error("Ignoring subscribe for unexpected characteristic: \(pair.1)")
            return
        }
        guard addListener(pair.0) != nil else {
            logger.error("Ignoring subscription request from non-candidate: \(pair.0)")
            return
        }
        // nothing else to do
    }
    
    private func noticeUnsubscription(_ pair: (CBCentral, CBCharacteristic)) {
        guard pair.1.uuid == BluetoothData.textUuid || pair.1.uuid == BluetoothData.disconnectUuid else {
            logger.error("Ignoring unsubscribe for unexpected characteristic: \(pair.1)")
            return
        }
        if let candidate = candidates.removeValue(forKey: pair.0) {
            logger.log("Unsubscribe/drop candidate \(candidate.id): \(pair.0)")
        } else if let listener = remotes.removeValue(forKey: pair.0) {
            logger.log("Unsubscribe/drop listener \(listener.id): \(pair.0)")
            dropRemoteSubject.send(listener)
        } else {
            logger.error("Ignoring unsubscription request from already-dropped candidate or listener: \(pair.0)")
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
        if characteristic.uuid == BluetoothData.whisperNameUuid {
            logger.log("Request is for name")
            request.value = Data(PreferenceData.userName().utf8)
            factory.respondToReadRequest(request: request, withCode: .success)
        } else if characteristic.uuid == BluetoothData.textUuid {
            logger.log("Request is for complete text")
            guard let listener = addListener(request.central) else {
                logger.error("Refusing read text request from non-listener/non-candidate \(request.central)")
                factory.respondToReadRequest(request: request, withCode: .insufficientAuthorization)
                return
            }
            // in this transport, the "request to read" is interpreted as a fill replay request and acknowledged
            let chunk = TextProtocol.ProtocolChunk.replayRequest(hint: "all")
            request.value = TextProtocol.ProtocolChunk.acknowledgeRead(hint: "all").toData()
            factory.respondToReadRequest(request: request, withCode: .success)
            receivedChunkSubject.send((remote: listener, chunk: chunk))
        } else if request.characteristic.uuid == BluetoothData.disconnectUuid {
            if let candidate = candidates.removeValue(forKey: request.central) {
                logger.log("Request is to drop candidate \(candidate.id): \(request.central)")
            } else if let listener = remotes.removeValue(forKey: request.central) {
                logger.log("Request is to drop listener \(listener.id): \(request.central)")
                dropRemoteSubject.send(listener)
            } else {
                logger.error("Ignoring unsubscription request from non-candidate, non-listener: \(request.central)")
                return
            }
            request.value = Data()
            factory.respondToReadRequest(request: request, withCode: .success)
        } else {
            logger.error("Got a read request for an unexpected characteristic: \(characteristic)")
            factory.respondToReadRequest(request: request, withCode: .attributeNotFound)
        }
    }
    
    private func processWriteRequests(_ requests: [CBATTRequest]) {
        guard let request = requests.first else {
            fatalError("Got an empty write request sequence")
        }
        guard requests.count == 1 else {
            logger.error("Got multiple listener requests in a batch: \(requests)")
            factory.respondToWriteRequest(request: request, withCode: .requestNotSupported)
            return
        }
        guard request.characteristic.uuid == BluetoothData.listenNameUuid else {
            logger.error("Got a write request for an unexpected characteristic: \(request)")
            factory.respondToWriteRequest(request: request, withCode: .unlikelyError)
            return
        }
        guard let value = request.value,
              let idAndName = String(data: value, encoding: .utf8)
        else {
            logger.error("Got an empty listener name value: \(request)")
            factory.respondToWriteRequest(request: request, withCode: .invalidAttributeValueLength)
            return
        }
        let parts = idAndName.split(separator: "|", maxSplits: 1)
        guard parts.count == 2 else {
            logger.error("Got an invalid format for listener name: \(idAndName)")
            factory.respondToWriteRequest(request: request, withCode: .unlikelyError)
            return
        }
        let candidate = Remote(central: request.central, id: String(parts[0]), name: String(parts[1]))
        guard !droppedRemotes.contains(candidate.id) else {
            // dropped listeners cannot be re-aquired in this session
            logger.log("Refusing name write request from dropped listener \(candidate.id)")
            factory.respondToWriteRequest(request: request, withCode: .insufficientAuthorization)
            return
        }
        candidates[request.central] = candidate
        logger.log("Received id \(candidate.id), name '\(candidate.name)' from candidate \(request.central)")
        factory.respondToWriteRequest(request: request, withCode: .success)
    }
    
    private func processReadyToUpdate(_ ignore: ()) {
        updateListeners()
    }
    
    // MARK: Internal types, properties, and methods
        
    final class Subscriber: TransportRemote {
        var id: String
        var name: String
        
        fileprivate var central: CBCentral
        
        fileprivate init(central: CBCentral, id: String, name: String) {
            self.central = central
            self.id = id
            self.name = name
        }
    }
    
    private var factory = BluetoothFactory.shared
    private var remotes: [CBCentral: Remote] = [:]
    private var liveText: String = ""
    private var pendingChunks: [TextProtocol.ProtocolChunk] = []
    private var directedChunks: [CBCentral: [TextProtocol.ProtocolChunk]] = [:]
    private var advertisingInProgress = false
    private weak var adTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var candidates: [CBCentral: Remote] = [:]
    private var advertisers: [CBPeripheral: String] = [:]
    private var droppedRemotes: [String] = []
    private var whisperService: CBMutableService?
    private var isInBackground = false
    
    init() {
        logger.log("Initializing bluetooth whisper transport")
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
            .sink { [weak self] in self?.processReadyToUpdate($0) }
            .store(in: &cancellables)
    }
    
    deinit {
        logger.log("Destroying WhisperView model")
        cancellables.cancel()
    }

    /// Send pending chunks to listeners
    private func updateListeners() {
        guard !remotes.isEmpty else {
            // logger.debug("No listeners to update, dumping pending changes")
            pendingChunks.removeAll()
            directedChunks.removeAll()
            return
        }
        // prioritize readers over subscribers, because we want to hold
        // the changes to live text until the readers are caught up
        if !directedChunks.isEmpty {
            logger.log("Updating reading listeners...")
            while let (listener, chunks) = directedChunks.first {
                while let chunk = chunks.first {
                    let sendOk = factory.updateValue(value: chunk.toData(),
                                                     characteristic: BluetoothData.whisperTextCharacteristic,
                                                     central: listener)
                    if sendOk {
                        if chunks.count == 1 {
                            directedChunks.removeValue(forKey: listener)
                        } else {
                            directedChunks[listener]!.removeFirst()
                        }
                    } else {
                        return
                    }
                }
            }
        } else if !pendingChunks.isEmpty {
            logger.debug("Updating subscribed listeners (\(self.pendingChunks.count) chunks)...")
            while let chunk = pendingChunks.first {
                let sendOk = factory.updateValue(value: chunk.toData(),
                                               characteristic: BluetoothData.whisperTextCharacteristic)
                if sendOk {
                    pendingChunks.removeFirst()
                } else {
                    return
                }
            }
        }
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
        factory.advertise(services: [BluetoothData.whisperServiceUuid])
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
        advertisers.removeAll()
        advertisingInProgress = false
        if let timer = adTimer {
            // manual cancellation: invalidate the running timer
            adTimer = nil
            timer.invalidate()
        }
    }
    
    private func addListener(_ central: CBCentral) -> Remote? {
        if let listener = remotes[central] {
            // we've already connected this listener
            return listener
        }
        guard let candidate = candidates.removeValue(forKey: central) else {
            // can't add this central as a listener: it hasn't completed its handshake with us
            return nil
        }
        logger.log("Candidate \(candidate.id) (\(candidate.name)) has become a listener")
        remotes[central] = candidate
        addRemoteSubject.send(candidate)
        return candidate
    }
    
    private func removeAllListeners() {
        for listener in remotes.values {
            dropRemoteSubject.send(listener)
        }
        remotes.removeAll()
    }
}
