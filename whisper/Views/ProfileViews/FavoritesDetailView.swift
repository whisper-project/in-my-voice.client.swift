// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct FavoritesDetailView: View {
#if targetEnvironment(macCatalyst)
	@Environment(\.dismiss) private var dismiss
#endif
	@AppStorage("elevenlabs_api_key_preference") private var apiKey: String?
	@AppStorage("elevenlabs_voice_id_preference") private var voiceId: String?

	@Binding var path: NavigationPath
	var use: ((Favorite?) -> Void)?
	var f: Favorite

	@State var name: String = ""
	@State var newName: String = ""
	@State var text: String = ""
	@State var newText: String = ""
	@State var groups: Set<FavoritesGroup> = Set()
	@State var allGroups: [FavoritesGroup] = []
	@StateObject private var fp = UserProfile.shared.favoritesProfile

	var body: some View {
		Form {
			Section(header: Text("Favorite Name")) {
				HStack (spacing: 15) {
					TextField("Favorite Name", text: $newName)
						.lineLimit(nil)
						.submitLabel(.done)
						.textInputAutocapitalization(.never)
						.disableAutocorrection(true)
						.onSubmit { updateNameAndText() }
					Button("Submit", systemImage: "checkmark.square.fill") { updateNameAndText() }
						.labelStyle(.iconOnly)
						.disabled(newName.isEmpty || newName == f.name)
					Button("Reset", systemImage: "x.square.fill") { newName = name }
						.labelStyle(.iconOnly)
						.disabled(newName == name)
				}
				.buttonStyle(.borderless)
			}
			Section(header: Text("Favorite Text")) {
				HStack (spacing: 15) {
					TextField("Favorite Text", text: $newText)
						.lineLimit(nil)
						.submitLabel(.done)
						.textInputAutocapitalization(.sentences)
						.onSubmit { updateNameAndText() }
					Button("Submit", systemImage: "checkmark.square.fill") { updateNameAndText() }
						.labelStyle(.iconOnly)
						.disabled(newText.isEmpty || newText == f.text)
					Button("Reset", systemImage: "x.square.fill") { newText = text }
						.labelStyle(.iconOnly)
						.disabled(newText == text)
				}
				.buttonStyle(.borderless)
			}
			if let use = use {
				Button("Send to Listeners", action: { use(f) })
			}
			if ElevenLabs.isEnabled() {
				Section(header: Text("ElevenLabs Voice Generation"),
						footer: Text("ElevenLabs remembers the last speech generated for each favorite")) {
					Button("Listen to Existing", action: { f.speakText() })
					Button("Generate and Listen to New", action: { f.regenerateText() })
				}
			} else {
				Section(header: Text("Apple Voice Generation"),
						footer: Text("Apple generates the speech new each time a favorite is used")) {
					Button("Listen to Sample", action: { f.speakText() })
				}
			}
			Section(header: Text("Groups")) {
				List {
					ForEach(allGroups) { g in
						HStack(spacing: 15) {
							Button("Add/Remove", systemImage: groups.contains(g) ? "checkmark.square" : "square") {
								toggleGroup(g)
							}
							.labelStyle(.iconOnly)
							.font(.title)
							Text(g.name)
						}
					}
				}
			}
		}
		.navigationTitle("Favorite Details")
		.navigationBarTitleDisplayMode(.inline)
		.onChange(of: fp.timestamp, initial: true, updateFromProfile)
		.onChange(of: apiKey, updateFromProfile)
		.onChange(of: voiceId, updateFromProfile)
	}

	func updateFromProfile() {
		name = f.name
		newName = name
		text = f.text
		newText = text
		groups = f.groups
		allGroups = fp.allGroups()
	}

	func updateNameAndText() {
		if (newName != name && !newName.isEmpty) {
			fp.renameFavorite(f, to: newName)
		}
		if (newText != text && !newText.isEmpty) {
			fp.updateFavoriteText(f, to: newText)
		}
	}

	func toggleGroup(_ g: FavoritesGroup) {
		if groups.contains(g) {
			g.remove(f)
		} else {
			g.add(f)
		}
	}
}
