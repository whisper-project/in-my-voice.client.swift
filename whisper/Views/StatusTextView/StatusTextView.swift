// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct StatusTextView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var size: FontSizes.FontSize
    @Binding var text: String
    
    var body: some View {
        HStack (spacing: 5) {
            Button {
                self.size = FontSizes.nextSmaller(self.size)
            } label: {
                Image(systemName: "chevron.down.circle")
            }
            .disabled(size == .normal)
            Button {
                self.size = FontSizes.nextLarger(self.size)
            } label: {
                Image(systemName: "chevron.up.circle")
            }
            .disabled(size == .xxxxlarge)
            .padding(EdgeInsets(top: 0, leading: 5, bottom: 0, trailing: 10))
            Text(text)
                .font(FontSizes.fontFor(.xsmall))
                .foregroundColor(colorScheme == .light ? lightLiveTextColor : darkLiveTextColor)
        }
        .font(FontSizes.fontFor(.small))
    }
}

struct StatusTextViewModel_Previews: PreviewProvider {
    static var size: Binding<FontSizes.FontSize> = Binding(get: { return .normal }, set: { _ = $0 })
    static var text: Binding<String> = Binding(get: { return "This is some generic status text"}, set: { _ = $0 })
    static var previews: some View {
        StatusTextView(size: size, text: text)
    }
}
