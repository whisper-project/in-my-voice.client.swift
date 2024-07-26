// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct StatusTextView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var text: String
    var mode: OperatingMode
	var conversation: (any Conversation)?

	private var shareLinkUrl: URL {
		if let c = conversation {
			return URL(string: PreferenceData.publisherUrl(c))!
		} else {
			return URL(string: "https://localhost")!
		}
	}

    private let linkText = UIDevice.current.userInterfaceIdiom == .phone ? "Link" : "Send Listen Link"
    
    var body: some View {
		HStack (spacing: 20) {
			if let c = conversation {
				ShareLink(linkText, item: shareLinkUrl)
					.font(FontSizes.fontFor(name: .xsmall))
			}
			Text(text)
				.font(FontSizes.fontFor(name: .xsmall))
				.foregroundColor(colorScheme == .light ? lightLiveTextColor : darkLiveTextColor)
		}
    }
}

#Preview {
	StatusTextView(text: makeBinding("Generic status text"), mode: .listen, conversation: nil)
}

#Preview {
	StatusTextView(text: makeBinding("Generic status text"), mode: .whisper, conversation: nil)
}

#Preview {
	StatusTextView(text: makeBinding("Generic status text"), mode: .whisper, conversation: UserProfile.shared.whisperProfile.fallback)
}

#Preview {
	StatusTextView(text: makeBinding("Generic status text"), mode: .listen, conversation: UserProfile.shared.whisperProfile.fallback)
}
