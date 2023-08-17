// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine

enum TransportStatus {
    case off(String)
    case on
    case disabled(String)
}

enum TransportDiscovery {
    case automatic
    case manual(String)
}

protocol TransportLayer {
    var statusSubject: CurrentValueSubject<TransportStatus, Never> { get }
}

protocol TransportRemote: Identifiable {
    var id: String { get }
    var name: String { get }
}

protocol Transport {
    associatedtype Remote: TransportRemote
    associatedtype Layer: TransportLayer
    
    var layer: Layer { get }
    
    var addRemoteSubject: PassthroughSubject<Remote, Never> { get }
    var dropRemoteSubject: PassthroughSubject<Remote, Never> { get }
    var receivedChunkSubject: PassthroughSubject<(remote: Remote, chunk: TextProtocol.ProtocolChunk), Never> { get }

    func start() -> TransportDiscovery
    func stop()
    
    func startDiscovery() -> TransportDiscovery
    func stopDiscovery()
    
    func goToBackground()
    func goToForeground()
    
    func sendChunks(chunks: [TextProtocol.ProtocolChunk])
    func sendChunks(remote: Remote, chunks: [TextProtocol.ProtocolChunk])

    func drop(remote: Remote)
}
