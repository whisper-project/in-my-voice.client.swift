// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct FavoritesDetailView: View {
#if targetEnvironment(macCatalyst)
	@Environment(\.dismiss) private var dismiss
#endif

	@Binding var path: NavigationPath
	var f: Favorite

	@State var name: String = ""
	@State var newName: String = ""
	@State var text: String = ""
	@State var newText: String = ""
	@State var tags: Set<Group> = Set()
	@State var allGroups: [Group] = []
	@StateObject private var profile = UserProfile.shared

	var body: some View {
		Form {
			Section(header: Text("Favorite Name")) {
				HStack (spacing: 15) {
					TextField("Favorite Name", text: $newName)
						.lineLimit(nil)
						.submitLabel(.done)
						.textInputAutocapitalization(.never)
						.disableAutocorrection(true)
						.onSubmit { updateName() }
					Button("Submit", systemImage: "checkmark.square.fill") { updateName() }
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
						.onSubmit { updateText() }
					Button("Submit", systemImage: "checkmark.square.fill") { updateText() }
						.labelStyle(.iconOnly)
						.disabled(newText.isEmpty || newText == f.text)
					Button("Reset", systemImage: "x.square.fill") { newText = text }
						.labelStyle(.iconOnly)
						.disabled(newText == text)
				}
				.buttonStyle(.borderless)
			}
			Section(header: Text("Groups")) {
				List {
					ForEach(allGroups) { g in
						HStack(spacing: 15) {
							Button("Add/Remove", systemImage: tags.contains(g) ? "checkmark.square" : "square") {
								toggleTag(g)
							}
							.labelStyle(.iconOnly)
							.font(.title)
							Text(g.name)
						}
					}
				}
			}
		}
		.navigationTitle("Details")
		.navigationBarTitleDisplayMode(.inline)
		.onChange(of: profile.timestamp, initial: true, updateFromProfile)
	}

	func updateFromProfile() {
		name = f.name
		newName = name
		text = f.text
		newText = text
		tags = f.tagSets
		allGroups = profile.favoritesProfile.allGroups()
	}

	func updateName() {
		if (newName != name && !newName.isEmpty) {
			profile.favoritesProfile.renameFavorite(f, to: newName)
		}
		updateFromProfile()
	}

	func updateText() {
		if (newText != text && !newText.isEmpty) {
			f.updateText(newText)
		}
		updateFromProfile()
	}

	func toggleTag(_ g: Group) {
		if tags.contains(g) {
			g.remove(f)
		} else {
			g.add(f)
		}
		updateFromProfile()
	}

	private func addTag() {
		logger.info("Creating new name")
		let g = profile.favoritesProfile.newGroup()
		g.add(f)
		updateFromProfile()
		path.append(g)
	}
}
