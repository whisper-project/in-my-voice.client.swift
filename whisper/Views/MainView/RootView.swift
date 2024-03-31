// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct RootView: View {
	@Environment(\.openWindow) private var openWindow
	@Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

	@State var mode: OperatingMode = .ask
	@State var conversation: (any Conversation)? = nil
	@State var showWarning: Bool = false
	@State var warningMessage: String = ""

	let profile = UserProfile.shared

    var body: some View {
		MainView(mode: $mode, conversation: $conversation)
			.onAppear {
				profile.update()
				if (mode != .listen) {
					conversation = nil
				}
			}
			.onOpenURL { urlObj in
				guard !profile.username.isEmpty else {
					warningMessage = "You must create your initial profile before you can listen."
					showWarning = true
					return
				}
				let url = urlObj.absoluteString
				guard let cid = PreferenceData.publisherUrlToConversationId(url: url) else {
					logger.warning("Ignoring invalid universal URL: \(url)")
					warningMessage = "There is no whisperer at that link. Please get a new link and try again."
					showWarning = true
					return
				}
				logger.log("Handling valid universal URL: \(url)")
				if mode == .ask {
					conversation = profile.listenProfile.fromLink(cid)
					mode = .listen
				} else if (supportsMultipleWindows) {
					openWindow(value: profile.listenProfile.fromLink(cid))
				} else {
					let activity = mode == .whisper ? "whispering" : "listening"
					warningMessage = "Already \(activity) to someone else. Stop \(activity) and click the link again."
					showWarning = true
				}
			}
			.alert("Cannot Listen", isPresented: $showWarning,
				   actions: { Button("OK", action: { })}, message: { Text(warningMessage) })
    }
}

#Preview {
    RootView()
}
