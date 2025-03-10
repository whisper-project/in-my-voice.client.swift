// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

func makeBinding<T>(_ initialValue: T) -> Binding<T> {
    var value = initialValue
    return Binding<T>(get: { return value }, set: { value = $0 })
}
