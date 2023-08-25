// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine

final class DribbleFactory: TransportFactory {
    typealias Publisher = DribbleWhisperTransport
    typealias Subscriber = DribbleListenTransport
    
    static let shared = DribbleFactory()
    
    var statusSubject: CurrentValueSubject<TransportStatus, Never> = .init(.on)
    
    var publisherInfo: TransportDiscovery = .automatic
    
    func publisher() -> Publisher {
        return Publisher()
    }
    
    func subscriber(_ publisherInfo: TransportDiscovery) throws -> Subscriber {
        guard case .automatic = publisherInfo else {
            throw PublisherSubscriberMismatch.manualPublisherAutomaticSubscriber
        }
        return Subscriber()
    }
}
