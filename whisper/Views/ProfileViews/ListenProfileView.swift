// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct ListenProfileView: View {
	@Environment(\.scenePhase) private var scenePhase
	#if targetEnvironment(macCatalyst)
	@Environment(\.dismiss) private var dismiss
	#endif

	var maybeListen: ((ListenConversation?) -> Void)?

    @State private var conversations: [ListenConversation] = []
	@StateObject private var profile = UserProfile.shared

    var body: some View {
		NavigationStack {
			VStack(alignment: .center, spacing: 20) {
				if (!conversations.isEmpty) {
					VStack(alignment: .leading) {
						ForEach(conversations) { c in
							HStack(spacing: 10) {
								Button("Listen", systemImage: "ear") {
									logger.info("Hit listen button on \(c.id) (\(c.name))")
									maybeListen?(c)
								}
								Text("\(c.name) with \(c.ownerName)").lineLimit(nil)
								Spacer(minLength: 25)
								Button("Delete", systemImage: "delete.left") {
									logger.info("Hit delete button on \(c.id) (\(c.name))")
									profile.listenProfile.delete(c.id)
									updateFromProfile()
								}
							}
							.labelStyle(.iconOnly)
							.buttonStyle(.borderless)
						}
						Spacer()
					}
				} else {
					Text("(No past conversations)")
						.padding()
				}
				#if DEBUG
				ListenLinkView(maybeListen: maybeListen)
				#endif
			}
			.toolbarTitleDisplayMode(.large)
			.navigationTitle("Conversations")
			#if targetEnvironment(macCatalyst)
			.toolbar {
				Button(action: { dismiss() }, label: { Text("Close") } )
			}
			#endif
			.padding(10)
			.onChange(of: profile.timestamp, initial: true, updateFromProfile)
		}
		.onChange(of: scenePhase, initial: true, profile.update)
		.onDisappear(perform: profile.update)
    }
    
    func updateFromProfile() {
		conversations = profile.listenProfile.conversations()
    }
}

#if DEBUG
struct ListenLinkView: View {
	var maybeListen: ((ListenConversation?) -> Void)?

	@State var link: String = ""

	var body: some View {
		Form {
			Section("Paste link here to listen") {
				TextField("Conversation link", text: $link)
					.onSubmit {
						if let id = PreferenceData.publisherUrlToConversationId(url: link) {
							let conversation = UserProfile.shared.listenProfile.fromLink(id)
							maybeListen?(conversation)
						} else {
							link = "Not valid: \(link)"
						}
					}
			}
		}
	}
}
#endif

#Preview {
    ListenProfileView()
}
