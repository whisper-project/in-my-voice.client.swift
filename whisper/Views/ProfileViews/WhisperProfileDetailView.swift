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
	@StateObject var profile = UserProfile.shared

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
				ShareLink("Listen link", item: PreferenceData.publisherUrl(conversation))
			}
			Section(header: allowedParticipants.isEmpty ? Text("No Allowed Participants") : Text("Allowed Participants")) {
				List {
					ForEach(allowedParticipants) { info in
						HStack {
							Text(info.username)
							Spacer(minLength: 25)
							Button("Delete") {
								profile.whisperProfile.removeListener(conversation, profileId: info.id)
								updateFromProfile()
							}
						}
						.buttonStyle(.borderless)
					}
				}
			}
		}
		.onChange(of: profile.timestamp, initial: true, updateFromProfile)
	}

	func updateFromProfile() {
		name = conversation.name
		newName = name
		wasDefault = conversation == profile.whisperProfile.fallback
		isDefault = wasDefault
		allowedParticipants = profile.whisperProfile.listeners(conversation)
	}

	func updateConversation() {
		if (newName != name && !newName.isEmpty) {
			profile.whisperProfile.rename(conversation, name: newName)
		}
		if (isDefault != wasDefault) {
			profile.whisperProfile.fallback = conversation
		}
		updateFromProfile()
	}
}

#Preview {
	WhisperProfileDetailView(conversation: UserProfile.shared.whisperProfile.fallback)
}
