// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine

final class TcpWhisperTransport: PublishTransport {
    // MARK: protocol properties and methods
    typealias Remote = Listener
    
    var addRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var dropRemoteSubject: PassthroughSubject<Remote, Never> = .init()
    var receivedChunkSubject: PassthroughSubject<(remote: Remote, chunk: TextProtocol.ProtocolChunk), Never> = .init()
    
    func start(commFailure: @escaping () -> Void) {
        logger.log("Starting TCP whisper transport")
        self.commFailure = commFailure
        getTokenRequest(mode: .whisper, publisherId: PreferenceData.clientId, callback: receiveTokenRequest)
    }
    
    func stop() {
        logger.log("Stopping TCP whisper Transport")
    }
    
    func goToBackground() {
    }
    
    func goToForeground() {
    }
    
    func send(remote: Listener, chunks: [TextProtocol.ProtocolChunk]) {
        fatalError("'send' not yet implemented")
    }
    
    func drop(remote: Listener) {
        fatalError("'drop' not yet implemented")
    }
    
    func publish(chunks: [TextProtocol.ProtocolChunk]) {
        fatalError("'publish' not yet implemented")
    }
    
    // MARK: Internal types, properties, and initialization
    final class Listener: TransportRemote {
        let id: String
        var name: String
        
        init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }
    
    private var tokenRequest: String?
    private var commFailure: (() -> Void)?

    init(_ url: String) {
        guard url.hasSuffix(PreferenceData.clientId) else {
            fatalError("Tcp whisper transport can only publish on clientId channel")
        }
    }
    
    //MARK: Internal methods
    func receiveTokenRequest(_ token: String?) {
        guard token != nil else {
            commFailure?()
            return
        }
        self.tokenRequest = token
    }
}
