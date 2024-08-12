// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct FavoritesProfileView: View {
#if targetEnvironment(macCatalyst)
	@Environment(\.dismiss) private var dismiss
#endif

	@State private var path: NavigationPath = .init()
	@State private var allSet: Group = UserProfile.shared.favoritesProfile.allSet
	@State private var favorites: [Favorite] = []
	@StateObject private var profile = UserProfile.shared

	init(f: Favorite? = nil) {
		if let f = f {
			path.append(f)
		}
	}

	var body: some View {
		NavigationStack(path: $path) {
			List {
				ForEach(favorites) { f in
					NavigationLink(value: f) {
						Text(f.name)
					}
				}
				.onMove{ from, to in
					allSet.move(fromOffsets: from, toOffset: to)
					updateFromProfile()
				}
				.onDelete{ indexSet in
					allSet.onDelete(deleteOffsets: indexSet)
					updateFromProfile()
				}
			}
			.navigationDestination(for: Group.self, destination: { FavoritesGroupDetailView(path: $path, g: $0) })
			.navigationDestination(for: Favorite.self, destination: { FavoritesDetailView(path: $path, f: $0) })
			.navigationDestination(for: String.self, destination: { _ in FavoritesGroupView(path: $path) })
			.navigationTitle("Favorites")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
#if targetEnvironment(macCatalyst)
				ToolbarItem(placement: .topBarLeading) {
					Button(action: { dismiss() }, label: { Text("Close") } )
				}
#endif
				ToolbarItemGroup(placement: .topBarTrailing) {
					Button(action: addFavorite, label: { Image(systemName: "plus") } )
					EditButton()
					Button(action: showGroups, label: { Text("Groups") })
				}
			}
			.onChange(of: profile.timestamp, initial: true, updateFromProfile)
		}
		.onAppear(perform: profile.update)
		.onDisappear(perform: profile.update)
	}

	func addFavorite() {
		let f = profile.favoritesProfile.newFavorite(text: "This is a sample favorite.")
		updateFromProfile()
		path.append(f)
	}

	func showGroups() {
		path.append("Groups")
	}

	private func updateFromProfile() {
		allSet = profile.favoritesProfile.allSet
		favorites = allSet.favorites
	}
}

#Preview {
    FavoritesProfileView()
}
