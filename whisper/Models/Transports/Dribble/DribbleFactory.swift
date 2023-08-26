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
    
    var publisherUrl: TransportUrl = nil
    
    func publisher(_ publisherUrl: TransportUrl) -> Publisher {
        if publisherUrl != nil {
            logger.warning("Ignoring the publisher URL given to the Dribble whisper transport")
        }
        return Publisher()
    }
    
    func subscriber(_ publisherUrl: TransportUrl) -> Subscriber {
        if publisherUrl != nil {
            logger.warning("Ignoring the publisher URL given to the Dribble listen transport")
        }
        return Subscriber()
    }
}
