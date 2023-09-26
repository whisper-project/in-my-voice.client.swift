// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine
import Ably

final class TcpListenTransport: SubscribeTransport {
    // MARK: Protocol properties and methods
    typealias Remote = Whisperer
    
    var addRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var dropRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var receivedChunkSubject: PassthroughSubject<(remote: Remote, chunk: TextProtocol.ProtocolChunk), Never> = .init()
    
    func start(failureCallback: @escaping (String) -> Void) {
        logger.log("Starting TCP candidate transport")
        self.failureCallback = failureCallback
        self.authenticator = TcpAuthenticator(mode: .listen, publisherId: publisherId, callback: failureCallback)
        self.client = self.authenticator.getClient()
        self.client.connection.on(.connected) { _ in
            logger.log("TCP listen transport realtime client has connected")
        }
        self.client.connection.on(.disconnected) { _ in
            logger.log("TCP listen transport realtime client has disconnected")
        }
        whisperChannel = client.channels.get(channelName)
        whisperChannel?.on(.attached) { stateChange in
            logger.log("TCP listen transport realtime client has attached the whisper channel")
        }
        whisperChannel?.on(.detached) { stateChange in
            logger.log("TCP listen transport realtime client has detached the whisper channel")
        }
        whisperChannel?.attach()
        whisperChannel?.subscribe(clientId, callback: receiveMessage)
        whisperChannel?.subscribe("all", callback: receiveMessage)
        whisperChannel?.presence.subscribe(receivePresence)
        whisperChannel?.presence.enter(PreferenceData.userName())
    }
    
    func stop() {
        logger.info("Stopping TCP listen transport")
        whisperChannel?.detach()
    }
    
    func goToBackground() {
    }
    
    func goToForeground() {
    }
    
    func send(remote: Remote, chunks: [TextProtocol.ProtocolChunk]) {
        guard let remote = candidates[remote.id] else {
            logger.error("Ignoring request to send chunk to a non-candidate: \(remote.id)")
            return
        }
        for chunk in chunks {
            whisperChannel?.publish(remote.id, data: chunk.toString(), callback: receiveErrorInfo)
        }
    }
    
    func drop(remote: Remote) {
        guard candidates[remote.id] != nil else {
            logger.error("Ignoring request to drop a non-candidate: \(remote.id)")
            return
        }
        // we only ever have one candidate and that's the whisperer.
        // Dropping the whisperer is a mistake.
        failureCallback?("User requested to disconnect")
    }
    
    func subscribe(remote: Remote) {
        // since we only ever have one candidate,
        // there's nothing to do here, because
        // we are already subscribed.
    }
    
    // MARK: Internal types, properties, and initialization
    final class Whisperer: TransportRemote {
        var id: String
        var name: String
        
        fileprivate init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }
    
    private var failureCallback: ((String) -> Void)?
    private var clientId: String
    private var publisherId: String
    private var authenticator: TcpAuthenticator!
    private var client: ARTRealtime!
    private var channelName: String
    private var whisperChannel: ARTRealtimeChannel?
    private var candidates: [String:Remote] = [:]

    init(_ url: String) {
        self.clientId = PreferenceData.clientId
        guard let remoteId = PreferenceData.publisherUrlToClientId(url: url) else {
            fatalError("Invalid TCP listen url: \(url)")
        }
        self.publisherId = remoteId
        self.channelName = "\(publisherId):whisper"
    }
    
    //MARK: Internal methods
    func receiveErrorInfo(_ error: ARTErrorInfo?) {
        if let error = error {
            failureCallback?(error.message)
        }
    }
    
    func receiveMessage(message: ARTMessage) {
        guard let name = message.name,
              (name == clientId || name == "all") else {
            logger.error("Ignoring a message not intended for this client: \(String(describing: message))")
            return
        }
        guard let sender = message.clientId,
              let remote = candidates[sender] else {
            logger.error("Ignoring a message from an unknown sender: \(String(describing: message))")
            return
        }
        guard let payload = message.data as? String,
              let chunk = TextProtocol.ProtocolChunk.fromString(payload)
        else {
            logger.error("Ignoring a message with a non-chunk payload: \(String(describing: message))")
            return
        }
        if chunk.isDropRequest() {
            guard chunk.text == clientId else {
                logger.error("Ignoring a drop request meant for someone else: \(chunk.text)")
                return
            }
            logger.info("Received a drop request")
            failureCallback?("Whisperer requested disconnection")
            return
        }
        receivedChunkSubject.send((remote: remote, chunk: chunk))
    }
    
    func receivePresence(message: ARTPresenceMessage) {
        guard let remoteId = message.clientId, let name = message.data as? String else {
            logger.error("Ignoring a presence message missing client or info: \(String(describing: message))")
            return
        }
        guard remoteId == publisherId else {
            logger.log("Ignoring a presence message not about the whisperer")
            return
        }
        switch message.action {
        case .present, .enter:
            guard candidates[remoteId] == nil else {
                logger.warning("Ignoring present/enter event for existing candidate \(remoteId)")
                return
            }
            let remote = Remote(id: remoteId, name: name)
            candidates[remoteId] = remote
            addRemoteSubject.send(remote)
        case .leave:
            guard let remote = candidates.removeValue(forKey: remoteId) else {
                logger.warning("Ignoring leave event for non-candidate \(remoteId)")
                return
            }
            dropRemoteSubject.send(remote)
            failureCallback?("The whisperer disconnected")
        case .update:
            guard let candidate = candidates[remoteId] else {
                logger.warning("Ignoring update event for non-candidate \(remoteId)")
                return
            }
            guard candidate.name == name else {
                logger.error("Ignoring disallowed name update for \(remoteId) from \(candidate.name) to \(name)")
                return
            }
        case .absent:
            logger.warning("Ignoring absent presence message for \(remoteId): \(String(describing: message))")
        @unknown default:
            logger.warning("Ignoring unknown presence message for \(remoteId): \(String(describing: message))")
        }
    }
}
