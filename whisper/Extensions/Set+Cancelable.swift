// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Combine

extension Set where Element: Cancellable {
    
    func cancel() {
        forEach { $0.cancel() }
    }
    
}
