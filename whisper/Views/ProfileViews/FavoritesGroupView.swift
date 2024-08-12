// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct FavoritesGroupView: View {
	@Binding var path: NavigationPath

	@State private var groups: [Group] = []
	@StateObject private var profile = UserProfile.shared

	var body: some View {
		List {
			ForEach(groups) { group in
				NavigationLink(value: group) {
					Text(group.name)
						.lineLimit(nil)
				}
			}
			.onDelete { indexSet in
				for index in indexSet {
					profile.favoritesProfile.deleteGroup(groups[index])
				}
				updateFromProfile()
			}
		}
		.navigationTitle("Groups")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			Button(action: addGroup, label: { Image(systemName: "plus") } )
			EditButton()
		}
		.onChange(of: profile.timestamp, initial: true, updateFromProfile)
		.onAppear(perform: profile.update)
		.onDisappear(perform: profile.update)
	}

	private func addGroup() {
		logger.info("Creating new tag")
		let group = profile.favoritesProfile.newGroup()
		updateFromProfile()
		path.append(group)
	}

	private func updateFromProfile() {
		groups = profile.favoritesProfile.allGroups()
	}
}
