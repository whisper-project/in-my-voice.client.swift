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

enum PublisherSubscriberMismatch: Error {
    case manualPublisherAutomaticSubscriber
    case automaticPublisherManualSubscriber
    case subscriberEqualsPublisher
}

protocol TransportFactory {
    associatedtype Publisher: PublishTransport
    associatedtype Subscriber: SubscribeTransport
    
    static var shared: Self { get }
    
    var publisherInfo: TransportDiscovery { get }
    
    var statusSubject: CurrentValueSubject<TransportStatus, Never> { get }
    
    func publisher() -> Publisher
    func subscriber(_ publisherInfo: TransportDiscovery) throws -> Subscriber
}

protocol TransportRemote: Identifiable {
    var id: String { get }
    var name: String { get }
}

typealias TransportSessionId = String

protocol Transport {
    associatedtype Remote: TransportRemote
    
    var addRemoteSubject: PassthroughSubject<Remote, Never> { get }
    var dropRemoteSubject: PassthroughSubject<Remote, Never> { get }
    var receivedChunkSubject: PassthroughSubject<(remote: Remote, chunk: TextProtocol.ProtocolChunk), Never> { get }

    func start() -> Bool
    func stop()
    
    func goToBackground()
    func goToForeground()
    
    func send(remote: Remote, chunks: [TextProtocol.ProtocolChunk])

    func drop(remote: Remote)
}

protocol PublishTransport: Transport {
    func publish(chunks: [TextProtocol.ProtocolChunk])
}

protocol SubscribeTransport: Transport {
    func subscribe(remote: Remote)
}
