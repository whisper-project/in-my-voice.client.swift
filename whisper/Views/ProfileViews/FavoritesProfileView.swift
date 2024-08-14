// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct FavoritesProfileView: View {
#if targetEnvironment(macCatalyst)
	@Environment(\.dismiss) private var dismiss
#endif

	var use: ((Favorite?) -> Void)? = nil
	var g: FavoritesGroup? = nil
	var f: Favorite? = nil

	@State private var path: NavigationPath = .init()
	@State private var allGroup: FavoritesGroup = UserProfile.shared.favoritesProfile.allGroup
	@State private var favorites: [Favorite] = []
	@StateObject private var up = UserProfile.shared
	@StateObject private var fp = UserProfile.shared.favoritesProfile

	var body: some View {
		NavigationStack(path: $path) {
			List {
				ForEach(favorites) { f in
					NavigationLink(value: f) {
						Text(f.name)
					}
				}
				.onMove{ from, to in allGroup.move(fromOffsets: from, toOffset: to) }
				.onDelete{ indexSet in allGroup.onDelete(deleteOffsets: indexSet) }
			}
			.navigationDestination(for: FavoritesGroup.self, destination: {
				FavoritesGroupDetailView(path: $path, g: $0)
			})
			.navigationDestination(for: Favorite.self, destination: {
				FavoritesDetailView(path: $path, use: use, f: $0)
			})
			.navigationDestination(for: String.self, destination: { _ in
				FavoritesGroupView(path: $path)
			})
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
			.onChange(of: fp.timestamp, initial: true, updateFromProfile)
		}
		.onAppear{
			up.update()
			// if we were given views, push them on the stack
			if let g = g {
				path.append("Groups")
				path.append(g)
			}
			if let f = f {
				path.append(f)
			}
		}
		.onDisappear(perform: up.update)
	}

	func addFavorite() {
		let f = fp.newFavorite(text: "This is a sample favorite.")
		path.append(f)
	}

	func showGroups() {
		path.append("Groups")
	}

	private func updateFromProfile() {
		allGroup = fp.allGroup
		favorites = allGroup.favorites
	}
}

#Preview {
    FavoritesProfileView()
}
