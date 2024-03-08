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
	@State private var myConversations: [WhisperConversation] = []
	@StateObject private var profile = UserProfile.shared

    var body: some View {
		NavigationStack {
			VStack(alignment: .leading, spacing: 20) {
				if (!myConversations.isEmpty) {
					Text("Conversations with Others").font(.title3)
				}
				if (!conversations.isEmpty) {
					List(conversations) { c in
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
				} else {
					Text("(None yet)")
				}
				if (!myConversations.isEmpty) {
					Text("My Conversations").font(.title3)
					List(myConversations) { c in
						HStack(spacing: 10) {
							Button("Listen", systemImage: "ear") {
								logger.info("Hit listen button on \(c.id) (\(c.name))")
								maybeListen?(profile.listenProfile.fromMyWhisperConversation(c))
							}
							Text("\(c.name)").lineLimit(nil)
						}
						.labelStyle(.iconOnly)
						.buttonStyle(.borderless)
					}
					.listStyle(.inset)
				}
				Spacer()
				#if DEBUG
				ListenLinkView(maybeListen: maybeListen)
				#endif
			}
			.navigationTitle("Listen")
			#if targetEnvironment(macCatalyst)
			.toolbar {
				Button(action: { dismiss() }, label: { Text("Close") } )
			}
			#endif
			.padding(10)
			.onChange(of: profile.timestamp, initial: true, updateFromProfile)
		}
		.onAppear(perform: profile.update)
		.onDisappear(perform: profile.update)
    }
    
    func updateFromProfile() {
		conversations = profile.listenProfile.conversations()
		myConversations = profile.userPassword.isEmpty ? [] : profile.whisperProfile.conversations()
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
