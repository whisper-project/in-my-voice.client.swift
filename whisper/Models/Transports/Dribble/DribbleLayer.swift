// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine

final class DribbleLayer: TransportLayer {
    static let shared = DribbleLayer()
    
    var statusSubject: CurrentValueSubject<TransportStatus, Never> = .init(.on)
}
