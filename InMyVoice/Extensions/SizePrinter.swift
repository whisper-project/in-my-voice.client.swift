// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

// this code lifted and modified from:
// https://stackoverflow.com/a/57577752/558006

struct SizePrinter: ViewModifier {
    var label: String
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear // we just want the reader to get triggered, so let's use an empty color
                        .onAppear {
                            print("\(label)'s size: \(proxy.size)")
                        }
                }
            )
    }
}

extension View {
    func printSize(label: String) -> some View {
        modifier(SizePrinter(label: label))
    }
}
