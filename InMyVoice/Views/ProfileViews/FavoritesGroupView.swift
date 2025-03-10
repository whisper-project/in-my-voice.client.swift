// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct FavoritesGroupView: View {
	@Binding var path: NavigationPath

	@State private var groups: [FavoritesGroup] = []
	@StateObject private var fp = UserProfile.shared.favoritesProfile

	var body: some View {
		Form {
			if groups.isEmpty {
				Section("No groups") {}
			} else {
				List {
					ForEach(groups) { group in
						NavigationLink(value: group) {
							Text(group.name)
								.lineLimit(nil)
						}
					}
					.onDelete { indices in
						fp.deleteGroups(indices: indices)
					}
					.onMove { from, to in
						fp.moveGroups(fromOffsets: from, toOffset: to)
					}
				}
			}
		}
		.navigationTitle("Groups")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			Button(action: addGroup, label: { Image(systemName: "plus") } )
			EditButton()
		}
		.onChange(of: fp.timestamp, initial: true, updateFromProfile)
	}

	private func addGroup() {
		logger.info("Creating new tag")
		let group = fp.newGroup()
		path.append(group)
	}

	private func updateFromProfile() {
		groups = fp.allGroups()
	}
}
