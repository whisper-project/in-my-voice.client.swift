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
	@State private var showListenEntry: Bool = false
	@StateObject private var profile = UserProfile.shared

    var body: some View {
		NavigationStack {
			chooseView()
				.navigationTitle("Listen Conversations")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
#if targetEnvironment(macCatalyst)
					ToolbarItem(placement: .topBarLeading) {
						Button(action: { dismiss() }, label: { Text("Close") } )
					}
#endif
					ToolbarItem(placement: .topBarTrailing) {
						Button(action: pasteConversation, label: { Image(systemName: "plus") } )
					}
				}
		}
		.sheet(isPresented: $showListenEntry, content: {
			ListenLinkView(maybeListen: maybeListen, show: $showListenEntry)
		})
		.onChange(of: profile.timestamp, initial: true, updateFromProfile)
		.onAppear(perform: profile.update)
		.onDisappear(perform: profile.update)
    }

	func pasteConversation() {
		if let url = UIPasteboard.general.url,
		   let conversation = UserProfile.shared.listenProfile.fromLink(url.absoluteString) {
			maybeListen?(conversation)
		} else if let str = UIPasteboard.general.string,
		   let conversation = UserProfile.shared.listenProfile.fromLink(str) {
			maybeListen?(conversation)
		} else {
			showListenEntry = true
		}
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
				Spacer()
				ShareLink("", item: PreferenceData.publisherUrl(c))
					.font(.title)
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
				Spacer()
				ShareLink("", item: PreferenceData.publisherUrl(c))
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.borderless)
		}
	}
}

struct ListenLinkView: View {
	var maybeListen: ((ListenConversation?) -> Void)?
	@Binding var show: Bool

	@State var link: String = ""
	@State var error: String? = nil

	var body: some View {
		Form {
			Section("Enter Listen Link") {
				TextField("Conversation link", text: $link, axis: .vertical)
					.lineLimit(3...10)
					.onChange(of: link) { old, new in
						if new.hasSuffix("\n") {
							link = old
							maybeJoin()
						} else {
							error = nil
						}
					}
					.submitLabel(.join)
					.textInputAutocapitalization(.never)
					.disableAutocorrection(true)
					.onSubmit(maybeJoin)
				if error != nil {
					Text("Sorry, that's not a valid listen link")
						.font(.subheadline)
				}
				Button("Join", action: maybeJoin)
			}
		}
	}

	func maybeJoin() {
		if let conversation = UserProfile.shared.listenProfile.fromLink(link) {
			show = false
			maybeListen?(conversation)
		} else {
			link = "Not valid: \(link)"
		}
	}
}

#Preview {
    ListenProfileView()
}
