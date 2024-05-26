// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct WhisperProfileView: View {
	@Environment(\.scenePhase) private var scenePhase
	#if targetEnvironment(macCatalyst)
	@Environment(\.dismiss) private var dismiss
	#endif

	var maybeWhisper: ((WhisperConversation?) -> Void)?

    @State private var rows: [Row] = []
    @State private var defaultConversation: WhisperConversation?
	@StateObject private var profile = UserProfile.shared

    var body: some View {
		NavigationStack {
			List {
				ForEach(rows) { r in
					NavigationLink(destination: WhisperProfileDetailView(conversation: r.conversation)) {
						HStack(spacing: 10) {
							Button("Whisper", systemImage: "mouth") {
								logger.info("Hit whisper button on \(r.conversation.id) (\(r.id))")
								maybeWhisper?(r.conversation)
							}
							.labelStyle(.iconOnly)
							.buttonStyle(.bordered)
							Text(r.id)
								.lineLimit(nil)
								.bold(r.conversation == defaultConversation)
						}
					}
				}
				.onDelete { indexSet in
					let conversations = rows.map{r in return r.conversation}
					indexSet.forEach{ profile.whisperProfile.delete(conversations[$0]) }
					updateFromProfile()
				}
			}
			.navigationTitle("Whisper Conversations")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				Button(action: addConversation, label: { Text("Add") } )
				EditButton()
				#if targetEnvironment(macCatalyst)
				Button(action: { dismiss() }, label: { Text("Close") } )
				#endif
			}
			.onChange(of: profile.timestamp, initial: true, updateFromProfile)
        }
		.onAppear(perform: profile.update)
		.onDisappear(perform: profile.update)
    }

	private func addConversation() {
		logger.info("Creating new conversation")
		profile.whisperProfile.new()
		updateFromProfile()
	}

	private struct Row: Identifiable {
		let id: String
		let conversation: WhisperConversation
	}

    private func updateFromProfile() {
		rows = profile.whisperProfile.conversations().map{ c in return Row(id: c.name, conversation: c) }
		defaultConversation = profile.whisperProfile.fallback
    }
}

#Preview {
    WhisperProfileView()
}
