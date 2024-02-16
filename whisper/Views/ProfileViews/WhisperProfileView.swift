// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct WhisperProfileView: View {
	#if targetEnvironment(macCatalyst)
	@Environment(\.dismiss) private var dismiss
	#endif

	var maybeWhisper: ((WhisperConversation?) -> Void)?

    @State private var conversations: [WhisperConversation] = []
    @State private var defaultConversation: WhisperConversation?

	private let profile = UserProfile.shared.whisperProfile

    var body: some View {
		NavigationStack {
			List {
				ForEach(conversations) { c in
					NavigationLink(destination: WhisperProfileDetailView(conversation: c)) {
						HStack(spacing: 15) {
							Text(c.name)
								.lineLimit(nil)
								.bold(c == defaultConversation)
							Spacer(minLength: 25)
							Button("Whisper", systemImage: "icloud.and.arrow.up") {
								logger.info("Hit whisper button on \(c.id) (\(c.name))")
								maybeWhisper?(c)
							}
							.labelStyle(.iconOnly)
							.buttonStyle(.bordered)
							Spacer().frame(width: 15)
						}
					}
				}
				.onDelete { indexSet in
					indexSet.forEach{ profile.delete(conversations[$0]) }
					updateFromProfile()
				}
			}
			.toolbarTitleDisplayMode(.large)
			.navigationTitle("Conversations")
			.toolbar {
				Button(action: addConversation, label: { Text("Add") } )
				EditButton()
				#if targetEnvironment(macCatalyst)
				Button(action: { dismiss() }, label: { Text("Close") } )
				#endif
			}
			.onAppear {
				updateFromProfile()
			}
        }
    }

	func addConversation() {
		logger.info("Creating new conversation")
		profile.new()
		updateFromProfile()
	}

    func updateFromProfile() {
		profile.update()
        conversations = profile.conversations()
        defaultConversation = profile.fallback
    }
}

#Preview {
    WhisperProfileView()
}
