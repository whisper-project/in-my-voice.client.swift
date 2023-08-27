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
        logger.info("Starting TCP listen transport...")
        self.failureCallback = failureCallback
        guard publisherId != PreferenceData.clientId else {
            failureCallback("Whisperer and listener must be on different devices")
            return
        }
    }
    
    func stop() {
        logger.info("Stopping TCP listen transport")
    }
    
    func goToBackground() {
    }
    
    func goToForeground() {
    }
    
    func send(remote: Remote, chunks: [TextProtocol.ProtocolChunk]) {
        fatalError("'send' not yet implemented")
    }
    
    func drop(remote: Remote) {
        fatalError("'drop' not yet implemented")
    }
    
    func subscribe(remote: Remote) {
        fatalError("'send' not yet implemented")
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
    
    private var publisherId: String!
    private var tokenRequest: String?
    private var failureCallback: ((String) -> Void)?
    private var authenticator: TcpAuthenticator
    private var client: ARTRealtime

    init(_ url: String) {
        guard let clientId = PreferenceData.publisherUrlToClientId(url: url) else {
            fatalError("Invalid TCP listen url: \(url)")
        }
        self.publisherId = clientId
        self.authenticator = TcpAuthenticator(mode: .whisper, publisherId: clientId)
        self.client = self.authenticator.getClient()
        self.client.connection.on(.connected) { _ in
            logger.log("TCP listen transport realtime client has connected")
        }
        self.client.connection.on(.disconnected) { _ in
            logger.log("TCP listen transport realtime client has disconnected")
        }
    }
    
    //MARK: Internal methods
    func receiveTokenRequest(_ token: String?) {
        guard token != nil else {
            failureCallback?("Couldn't get authorization to use the internet")
            return
        }
        self.tokenRequest = token
    }
}
