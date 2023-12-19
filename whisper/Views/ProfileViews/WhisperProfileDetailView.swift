// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct WhisperProfileDetailView: View {
	let c: Conversation

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
						.disabled(name.isEmpty || name == c.name)
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
		name = c.name
		newName = name
		wasDefault = c == profile.whisperDefault
		isDefault = wasDefault
	}

	func updateProfile() {
		var hasChanged = false
		if (newName != name && !newName.isEmpty) {
			hasChanged = true
			c.name = newName
		}
		if (isDefault != wasDefault) {
			hasChanged = true
			profile.whisperDefault = c
		}
		if hasChanged {
			profile.saveAsDefault()
		}
		updateFromProfile()
	}
}

#Preview {
	WhisperProfileDetailView(c: UserProfile.shared.whisperDefault)
}
