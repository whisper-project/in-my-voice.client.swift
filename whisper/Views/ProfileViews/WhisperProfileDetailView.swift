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

	private let profile = UserProfile.shared

	var body: some View {
		Form {
			Section(header: Text("Conversation Name")) {
				HStack {
					TextField("Conversation Name", text: $name)
						.lineLimit(nil)
						.submitLabel(.done)
						.textInputAutocapitalization(.never)
						.disableAutocorrection(true)
						.onSubmit { updateProfile() }
					Button("Submit", systemImage: "checkmark.square.fill") { updateProfile() }
						.labelStyle(.iconOnly)
						.disabled(name.isEmpty || name == conversation.name)
				}
				if (isDefault) {
					Text("This is your default conversation")
				} else {
					Button("Make this your default conversation") {
						isDefault = true
						updateProfile()
					}
				}
			}
			Section(header: Text("Allowed Participants")) {
				List {
					Text("This is not implemented yet.")
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
	}

	func updateProfile() {
		var hasChanged = false
		if (newName != name && !newName.isEmpty) {
			hasChanged = true
			conversation.name = newName
		}
		if (isDefault != wasDefault) {
			hasChanged = true
			profile.whisperDefault = conversation
		}
		if hasChanged {
			profile.saveAsDefault()
		}
		updateFromProfile()
	}
}

#Preview {
	WhisperProfileDetailView(conversation: UserProfile.shared.whisperDefault)
}
