// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct WhisperProfileDetailView: View {
	let conversation: Conversation

	@State var name: String = ""
	@State var newName: String = ""
	@State var isDefault: Bool = false
	@State var wasDefault: Bool = false
	@State var allowedParticipants: [UserProfile.ListenerInfo] = []

	private let profile = UserProfile.shared

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
				if (isDefault) {
					Text("This is your default conversation")
				} else {
					Button("Make this your default conversation") {
						isDefault = true
						updateConversation()
					}
				}
			}
			Section(header: allowedParticipants.isEmpty ? Text("No Allowed Participants") : Text("Allowed Participants")) {
				List {
					ForEach(allowedParticipants) { info in
						HStack {
							Text(info.username)
							Spacer(minLength: 25)
							Button("Delete") {
								profile.removeListenerFromWhisperConversation(profileId: info.id, conversation: conversation)
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
		wasDefault = conversation == profile.whisperDefault
		isDefault = wasDefault
		allowedParticipants = profile.listenersToWhisperConversation(conversation: conversation)
	}

	func updateConversation() {
		if (newName != name && !newName.isEmpty) {
			profile.renameWhisperConversation(c: conversation, name: newName)
		}
		if (isDefault != wasDefault) {
			profile.whisperDefault = conversation
		}
		updateFromProfile()
	}
}

#Preview {
	WhisperProfileDetailView(conversation: UserProfile.shared.whisperDefault)
}
