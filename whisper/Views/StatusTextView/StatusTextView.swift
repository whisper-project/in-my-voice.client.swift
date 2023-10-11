// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct StatusTextView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var text: String
    var mode: OperatingMode
    var publisherUrl: TransportUrl
    
    var body: some View {
        if mode == .listen {
            HStack { Text(text) }
                .font(FontSizes.fontFor(name: .xsmall))
                .foregroundColor(colorScheme == .light ? lightLiveTextColor : darkLiveTextColor)
        } else {
            HStack (spacing: 20) {
                let linkText = UIDevice.current.userInterfaceIdiom == .phone ? "Link" : "Send Listen Link"
                let url = publisherUrl ?? "https://localhost"
                ShareLink(linkText, item: URL(string: url)!)
                    .disabled(publisherUrl == nil)
                    .font(FontSizes.fontFor(name: .xsmall))
                Text(text)
                    .font(FontSizes.fontFor(name: .xsmall))
                    .foregroundColor(colorScheme == .light ? lightLiveTextColor : darkLiveTextColor)
            }
        }
    }
}

struct StatusTextViewModel_Previews: PreviewProvider {
    static var text: Binding<String> = Binding(get: { return "This is some generic status text"}, set: { _ = $0 })
    
    static var previews: some View {
        VStack {
            StatusTextView(text: text, mode: .whisper, publisherUrl: nil)
            StatusTextView(text: text, mode: .whisper, publisherUrl: "https://localhost/fake")
            StatusTextView(text: text, mode: .listen, publisherUrl: "https://localhost/fake")
        }
    }
}
