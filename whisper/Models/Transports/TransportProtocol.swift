// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine

enum TransportStatus {
    case off
    case disabled
    case waiting
    case on
}

protocol TransportFactory {
    associatedtype Publisher: PublishTransport
    associatedtype Subscriber: SubscribeTransport
    
    static var shared: Self { get }
    
    var statusSubject: CurrentValueSubject<TransportStatus, Never> { get }
    
    func publisher(_ conversation: Conversation?) -> Publisher
    func subscriber(_ conversation: Conversation?) -> Subscriber
}

protocol TransportRemote: Identifiable {
    var id: String { get }
    var name: String { get }
    var authorized: Bool { get set }
}

typealias TransportSessionId = String

protocol Transport {
    associatedtype Remote: TransportRemote
    
    var addRemoteSubject: PassthroughSubject<Remote, Never> { get }
    var dropRemoteSubject: PassthroughSubject<Remote, Never> { get }
    var contentSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> { get }
    var controlSubject: PassthroughSubject<(remote: Remote, chunk: WhisperProtocol.ProtocolChunk), Never> { get }

    func start(failureCallback: @escaping (String) -> Void)
    func stop()
    
    func goToBackground()
    func goToForeground()
    
    func sendControl(remote: Remote, chunks: [WhisperProtocol.ProtocolChunk])

    func drop(remote: Remote)
}

protocol PublishTransport: Transport {
    func sendContent(remote: Remote, chunks: [WhisperProtocol.ProtocolChunk])
    func publish(chunks: [WhisperProtocol.ProtocolChunk])
}

protocol SubscribeTransport: Transport {
    func subscribe(remote: Remote)
}
