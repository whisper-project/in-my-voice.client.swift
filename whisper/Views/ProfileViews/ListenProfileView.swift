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
			chooseView()
				.navigationTitle("Listen Conversations")
				.navigationBarTitleDisplayMode(.inline)
				#if targetEnvironment(macCatalyst)
				.toolbar {
					Button(action: { dismiss() }, label: { Text("Close") } )
				}
				#endif
		}
		.onChange(of: profile.timestamp, initial: true, updateFromProfile)
		.onAppear(perform: profile.update)
		.onDisappear(perform: profile.update)
    }
    
    func updateFromProfile() {
		conversations = profile.listenProfile.conversations()
		myConversations = profile.userPassword.isEmpty ? [] : profile.whisperProfile.conversations()
    }

	@ViewBuilder func chooseView() -> some View {
		if (myConversations.isEmpty) {
			if (conversations.isEmpty) {
				Form {
					Section("No prior conversations") {
						EmptyView()
					}
				}
			} else {
				listenConversations()
			}
		} else {
			Form {
				Section("Conversations with Others") {
					listenConversations()
				}
				Section("My Conversations") {
					whisperConversations()
				}
			}
		}
#if DEBUG
		ListenLinkView(maybeListen: maybeListen)
#endif
	}

	@ViewBuilder func listenConversations() -> some View {
		List(conversations) { c in
			HStack(spacing: 20) {
				Button("Listen", systemImage: "ear") {
					logger.info("Hit listen button on \(c.id) (\(c.name))")
					maybeListen?(c)
				}
				.font(.title)
				Text("\(c.name) with \(c.ownerName)").lineLimit(nil)
				Spacer(minLength: 25)
				Button("Delete", systemImage: "delete.left") {
					logger.info("Hit delete button on \(c.id) (\(c.name))")
					profile.listenProfile.delete(c.id)
					updateFromProfile()
				}
				.font(.title)
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.borderless)
		}
	}

	@ViewBuilder func whisperConversations() -> some View {
		List(myConversations) { c in
			HStack(spacing: 20) {
				Button("Listen", systemImage: "ear") {
					logger.info("Hit listen button on \(c.id) (\(c.name))")
					maybeListen?(profile.listenProfile.fromMyWhisperConversation(c))
				}
				.font(.title)
				Text("\(c.name)").lineLimit(nil)
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.borderless)
		}
	}
}

#if DEBUG
struct ListenLinkView: View {
	var maybeListen: ((ListenConversation?) -> Void)?

	@State var link: String = ""

	var body: some View {
		Form {
			Section("Paste link here to listen") {
				TextField("Conversation link", text: $link, axis: .vertical)
					.lineLimit(2...5)
					.onChange(of: link) { old, new in
						if new.hasSuffix("\n") {
							link = old
							maybeJoin()
						}
					}
					.submitLabel(.join)
					.textInputAutocapitalization(.never)
					.disableAutocorrection(true)
					.onSubmit(maybeJoin)
				Button("Join", action: maybeJoin)
			}
		}
	}

	func maybeJoin() {
		if let conversation = UserProfile.shared.listenProfile.fromLink(link) {
			maybeListen?(conversation)
		} else {
			link = "Not valid: \(link)"
		}
	}
}
#endif

#Preview {
    ListenProfileView()
}
