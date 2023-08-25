// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine

final class TcpFactory: TransportFactory {
    // MARK: protocol properties and methods
    typealias Publisher = TcpWhisperTransport
    typealias Subscriber = TcpListenTransport
    
    static let shared = TcpFactory()
    
    var statusSubject: CurrentValueSubject<TransportStatus, Never> = .init(.on)
    
    static var publishUrl: String = "\(PreferenceData.whisperServer)/subscribe/\(PreferenceData.clientId)"
    var publisherInfo: TransportDiscovery = .manual(publishUrl)
    
    func publisher() -> Publisher {
        return TcpWhisperTransport()
    }
    
    func subscriber(_ publisherInfo: TransportDiscovery) throws -> TcpListenTransport {
        guard case .manual(let publisher) = publisherInfo else {
            throw PublisherSubscriberMismatch.automaticPublisherManualSubscriber
        }
        guard !publisher.hasSuffix(PreferenceData.clientId) else {
            throw PublisherSubscriberMismatch.subscriberEqualsPublisher
        }
        return TcpListenTransport(publisher)
    }
    
    //MARK: private types, properties, and initialization
}
