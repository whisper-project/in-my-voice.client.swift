// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct WhisperStatusTextView: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var model: WhisperViewModel
	var conversation: (any Conversation)?

	private var shareLinkUrl: URL? {
		if let c = conversation {
			return URL(string: PreferenceData.publisherUrl(c))
		} else {
			return nil
		}
	}

    private let linkText = UIDevice.current.userInterfaceIdiom == .phone ? "Link" : "Send Listen Link"
	private let transcriptText = UIDevice.current.userInterfaceIdiom == .phone ? "Transcript" : "Send Transcript"

    var body: some View {
		HStack (spacing: 20) {
			if let url = shareLinkUrl {
				ShareLink(linkText, item: url)
					.font(FontSizes.fontFor(name: .xsmall))
			}
			Text(model.statusText)
				.font(FontSizes.fontFor(name: .xsmall))
				.foregroundColor(colorScheme == .light ? lightLiveTextColor : darkLiveTextColor)
			if model.transcriptId != nil {
				Button(action: { model.shareTranscript() }, label: {
					Label(transcriptText, systemImage: "eyeglasses")
				})
			}
		}
    }
}
