// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI
import UIKit

let settingsUrl = URL(string: UIApplication.openSettingsURLString)!

struct MainView: View {
    @Environment(\.colorScheme) private var colorScheme
	@Environment(\.openWindow) private var openWindow
	@Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    @Binding var mode: OperatingMode
    @Binding var conversation: (any Conversation)?

	@State var restart: Bool = false
    @StateObject private var model: MainViewModel = .init()
            
    var body: some View {
        switch mode {
        case .ask:
            VStack {
                Spacer()
                ChoiceView(mode: $mode, conversation: $conversation, transportStatus: $model.status)
                Spacer()
                Text("v\(versionString)")
                    .textSelection(.enabled)
                    .font(FontSizes.fontFor(name: .xxxsmall))
                    .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                    .padding(EdgeInsets(top: 20, leading: 0, bottom: 5, trailing: 0))
            }
			.alert("Conversation Paused", isPresented: $restart) {
				Button("OK") { mode = .listen }
				Button("Cancel") {}
			} message: {
				Text("The Whisperer has paused the conversation. Click OK to reconnect, Cancel to stop listening.")
			}
			.onAppear {
				// reset the title if we came from ListenView or WhisperView
				UIApplication.shared.firstKeyWindow?.windowScene?.title = nil
			}
        case .listen:
			ListenView(mode: $mode, restart: $restart, conversation: conversation as! ListenConversation)
        case .whisper:
			WhisperView(mode: $mode, conversation: conversation as! WhisperConversation)
        }
    }
}

#Preview {
	MainView(mode: makeBinding(.ask), conversation: makeBinding(nil))
}
