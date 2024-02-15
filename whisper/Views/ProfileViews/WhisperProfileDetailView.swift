// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct WhisperProfileDetailView: View {
	let conversation: WhisperConversation

	@State var name: String = ""
	@State var newName: String = ""
	@State var isDefault: Bool = false
	@State var wasDefault: Bool = false
	@State var allowedParticipants: [ListenerInfo] = []

	private let profile = UserProfile.shared.whisperProfile

	var body: some View {
		Form {
			Section(header: Text("Conversation Name")) {
				HStack (spacing: 15) {
					TextField("Conversation Name", text: $newName)
						.lineLimit(nil)
						.submitLabel(.done)
						.textInputAutocapitalization(.never)
						.disableAutocorrection(true)
						.onSubmit { updateConversation() }
					Button("Submit", systemImage: "checkmark.square.fill") { updateConversation() }
						.labelStyle(.iconOnly)
						.disabled(newName.isEmpty || newName == conversation.name)
					Button("Reset", systemImage: "x.square.fill") { newName = name }
						.labelStyle(.iconOnly)
						.disabled(newName == name)
				}
				.buttonStyle(.borderless)
			}
			Section(header: Text("Conversation Details")) {
				if (isDefault) {
					Text("This is your default conversation")
				} else {
					Button("Make this your default conversation") {
						isDefault = true
						updateConversation()
					}
				}
				ShareLink("Listen link", item: PreferenceData.publisherUrl(conversation.id))
			}
			Section(header: allowedParticipants.isEmpty ? Text("No Allowed Participants") : Text("Allowed Participants")) {
				List {
					ForEach(allowedParticipants) { info in
						HStack {
							Text(info.username)
							Spacer(minLength: 25)
							Button("Delete") {
								profile.removeListener(conversation, profileId: info.id)
								updateFromProfile()
							}
						}
						.buttonStyle(.borderless)
					}
				}
			}
		}
		.onAppear { updateFromProfile() }
	}

	func updateFromProfile() {
		name = conversation.name
		newName = name
		wasDefault = conversation == profile.fallback
		isDefault = wasDefault
		allowedParticipants = profile.listeners(conversation)
	}

	func updateConversation() {
		if (newName != name && !newName.isEmpty) {
			profile.rename(conversation, name: newName)
		}
		if (isDefault != wasDefault) {
			profile.fallback = conversation
		}
		updateFromProfile()
	}
}

#Preview {
	WhisperProfileDetailView(conversation: UserProfile.shared.whisperProfile.fallback)
}
