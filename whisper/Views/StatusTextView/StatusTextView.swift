// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct StatusTextView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var text: String
    
    var body: some View {
        HStack (spacing: 5) {
            Text(text)
                .font(FontSizes.fontFor(name: .xsmall))
                .foregroundColor(colorScheme == .light ? lightLiveTextColor : darkLiveTextColor)
        }
    }
}

struct StatusTextViewModel_Previews: PreviewProvider {
    static var text: Binding<String> = Binding(get: { return "This is some generic status text"}, set: { _ = $0 })
    
    static var previews: some View {
        StatusTextView(text: text)
    }
}
