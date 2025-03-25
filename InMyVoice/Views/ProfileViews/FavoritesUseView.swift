// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct FavoritesUseView: View {
	var use: (Favorite?) -> Void
	@Binding var group: FavoritesGroup

	@State private var favorites: [Favorite] = []
	@StateObject private var fp = FavoritesProfile.shared

	var body: some View {
		Form {
			Section(group == fp.allGroup ? "All" : group.name) {
				List {
					ForEach(favorites) { f in
						Button(action: { self.use(f) }) {
							Text(f.name)
						}
					}
				}
			}
		}
		.onChange(of: fp.timestamp, updateFromProfile)
		.onChange(of: group, updateFromProfile)
		.onAppear(perform: updateFromProfile)
	}

	private func updateFromProfile() {
		favorites = group.favorites
	}
}
