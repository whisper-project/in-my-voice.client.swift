// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation

fileprivate struct StoredFavorites: Codable {
	var favorites: [Favorite]
	var groupList: [String]
	var groupTable: [String: [String]]
}

final class Favorite: Identifiable, Comparable, Hashable, Codable {
	fileprivate(set) var profile: FavoritesProfile?
	fileprivate(set) var name: String
	fileprivate(set) var text: String
	fileprivate(set) var groups: Set<FavoritesGroup> = Set()
	fileprivate var speechHash: String?
	fileprivate var speechId: String?

	private enum CodingKeys: String, CodingKey {
		case name, text, speechHash, speechId
	}

	fileprivate init(profile: FavoritesProfile, name: String, text: String) {
		self.profile = profile
		self.name = name
		self.text = text
	}

	var id: String {
		get { name }
	}

	func hash(into hasher: inout Hasher) {
		name.hash(into: &hasher)
	}

	// depends on there never being two favorites with the same name
	static func == (lhs: Favorite, rhs: Favorite) -> Bool {
		lhs.name == rhs.name
	}

	// depends on there never being two favorites with the same name
	static func < (lhs: Favorite, rhs: Favorite) -> Bool {
		lhs.name < rhs.name
	}
	
	func speakText() {
		speakTextInternal(regenerate: false)
	}

	func regenerateText() {
		speakTextInternal(regenerate: true)
	}

	private func speakTextInternal(regenerate: Bool) {
		let memoize: SpeechCallback = { item in
			if let item = item {
				if item.hash != self.speechHash || item.historyId != self.speechId {
					self.speechHash = item.hash
					self.speechId = item.historyId
					self.profile?.save()
				}
			}
		}
		if regenerate {
			ElevenLabs.shared.forgetText(text)
		}
		ElevenLabs.shared.speakText(text: text, callback: memoize)
	}
}

final class FavoritesGroup: Identifiable, Hashable {
	fileprivate var profile: FavoritesProfile
	fileprivate(set) var name: String
	private(set) var favorites: [Favorite] = []

	fileprivate init(profile: FavoritesProfile, name: String) {
		self.profile = profile
		self.name = name
	}

	static func == (lhs: FavoritesGroup, rhs: FavoritesGroup) -> Bool {
		lhs === rhs
	}

	func hash(into hasher: inout Hasher) {
		name.hash(into: &hasher)
	}

	var id: String {
		get { self.name }
	}

	private func contains(name: String) -> Bool {
		favorites.contains(where: { $0.name == name })
	}

	private func contains(f: Favorite) -> Bool {
		favorites.contains(where: { $0 === f })
	}

	func add(_ f: Favorite) {
		guard !contains(name: f.name) else {
			return
		}
		addInternal(f)
		profile.save()
	}

	fileprivate func addInternal(_ f: Favorite, at: Int? = nil) {
		// caller guarantees that name is not in use
		if let i = at, i >= 0, i < favorites.count {
			favorites.insert(f, at: i)
		} else {
			self.favorites.append(f)
		}
		f.groups.insert(self)
	}

	func move(fromOffsets: IndexSet, toOffset: Int) {
		favorites.move(fromOffsets: fromOffsets, toOffset: toOffset)
		profile.save()
	}

	func onDelete(deleteOffsets: IndexSet) {
		let deleted = deleteOffsets.compactMap{ index in favorites[index] }
		guard self !== profile.allGroup else {
			// removing from the all set is a remove from the profile
			profile.deleteFavorites(deleted)
			return
		}
		favorites.remove(atOffsets: deleteOffsets)
		for d in deleted {
			d.groups.remove(self)
		}
		profile.save()
	}

	func remove(_ f: Favorite) {
		favorites.removeAll(where: { f === $0 })
		f.groups.remove(self)
		profile.save()
	}
}

final class FavoritesProfile: ObservableObject {
	static let shared = FavoritesProfile()

	@Published private(set) var timestamp: Int = 0

	private let saveName = PreferenceData.profileRoot + "FavoritesProfile"
	private var favoritesTable: [String: Favorite] = [:]
	private var lookupTable: [String: [Favorite]] = [:]
	private(set) var allGroup: FavoritesGroup! = nil
	private var groupTable: [String: FavoritesGroup] = [:]
	private var groupList: [FavoritesGroup] = []
	private var serverPassword: String = ""

	init() {
		allGroup = FavoritesGroup(profile: self, name: "")
		if !load() {
			_ = addFavoriteInternal(name: "Sample", text: "This is a sample favorite.", tags: [])
			save()
		}
	}

	private func toStored() -> StoredFavorites {
		let favorites = Array(allGroup.favorites)
		let groupList = groupList.map{ $0.name }
		let groupTable = groupTable.mapValues{ g in g.favorites.map{ $0.name } }
		let stored = StoredFavorites(favorites: favorites, groupList: groupList, groupTable: groupTable)
		return stored
	}

	private func fromStored(_ stored: StoredFavorites) {
		self.favoritesTable = [:]
		self.lookupTable = [:]
		self.groupTable = [:]
		self.groupList = []
		allGroup = FavoritesGroup(profile: self, name: "")
		for f in stored.favorites {
			f.profile = self
			_ = addFavoriteInternal(name: f.name, text: f.text)
			if let hash = f.speechHash, let id = f.speechId {
				logger.info("Favorite '\(f.name, privacy: .public)' has speech ID \(id, privacy: .public)")
				ElevenLabs.shared.memoizeText(f.text, hash: hash, id: id)
			}
		}
		for name in stored.groupList {
			let g = FavoritesGroup(profile: self, name: name)
			groupList.append(g)
			groupTable[name] = g
			if let members = stored.groupTable[name] {
				for name in members {
					if let f = favoritesTable[name] {
						g.addInternal(f)
					}
				}
			}
		}
	}

	private func load() -> Bool {
		if let data = Data.loadJsonFromDocumentsDirectory(saveName),
		   let stored = try? JSONDecoder().decode(StoredFavorites.self, from: data)
		{
			fromStored(stored)
			return true
		}
		return false
	}

	func downloadFavorites() {
		let dataHandler: (Data) -> Void = { data in
			if data.count == 0 {
				// no server favorites available, make no changes
			} else if let stored = try? JSONDecoder().decode(StoredFavorites.self, from: data) {
				self.fromStored(stored)
				self.save(localOnly: true)
			} else {
				let body = String(decoding: data, as: Unicode.UTF8.self)
				ServerProtocol.notifyAnomaly("Downloaded favorites are malformed: \(body)")
			}
		}
		ServerProtocol.downloadFavorites(dataHandler)
	}

	fileprivate func save(localOnly: Bool = false) {
		DispatchQueue.main.async {
			self.timestamp += 1
		}
		guard let data = try? JSONEncoder().encode(toStored()) else {
			ServerProtocol.notifyAnomaly("Cannot encode favorites profile for local save: \(self)")
			return
		}
		guard data.saveJsonToDocumentsDirectory(saveName) else {
			ServerProtocol.notifyAnomaly("Cannot save favorites profile to Documents directory")
			return
		}
		if !localOnly {
			ServerProtocol.uploadFavorites(data)
		}
	}

	private func addFavoriteInternal(name: String, text: String, tags: [String] = []) -> Favorite {
		// caller guarantees that the name isn't in use
		let f = Favorite(profile: self, name: name, text: text)
		favoritesTable[name] = f
		lookupTable[text] = (lookupTable[text] ?? []) + [f]
		allGroup.addInternal(f)
		for name in tags {
			if let tagSet = groupTable[name] {
				tagSet.addInternal(f)
			} else {
				ServerProtocol.notifyAnomaly("Ignoring unknown name (\(name)) in newFavorite(\(name))")
			}
		}
		return f
	}

	func lookupFavorite(text: String) -> [Favorite] {
		return lookupTable[text] ?? []
	}

	@discardableResult func newFavorite(text: String, name: String = "", tags: [String] = []) -> Favorite {
		var name = name.trimmingCharacters(in: .whitespaces)
		if name.isEmpty {
			name = "Favorite"
		}
		if favoritesTable[name] != nil {
			let root = name
			for i in 1... {
				name = "\(root) \(i)"
				if favoritesTable[name] == nil {
					break
				}
			}
		}
		let f = addFavoriteInternal(name: name, text: text.trimmingCharacters(in: .whitespacesAndNewlines), tags: tags)
		save()
		return f
	}

	@discardableResult func renameFavorite(_ f: Favorite, to: String) -> Bool {
		let to = to.trimmingCharacters(in: .whitespaces)
		guard favoritesTable[to] == nil else {
			return false
		}
		guard favoritesTable[f.name] === f else {
			ServerProtocol.notifyAnomaly("Ignore unknown favorite (\(f.name)) in renameFavorite")
			return false
		}
		favoritesTable.removeValue(forKey: f.name)
		f.name = to
		favoritesTable[to] = f
		save()
		return true
	}

	func updateFavoriteText(_ f: Favorite, to: String) {
		let text = to.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !to.isEmpty else {
			return
		}
		lookupTable[f.text] = (lookupTable[f.text] ?? []).filter{ $0 !== f }
		f.text = text
		f.speechId = nil
		f.speechHash = nil
		lookupTable[f.text] = (lookupTable[f.text] ?? []) + [f]
		save()
	}


	fileprivate func deleteFavorites(_ fs: [Favorite]) {
		for f in fs {
			guard f === favoritesTable[f.name] else {
				ServerProtocol.notifyAnomaly("Ignoring unknown favorite \(f.name) in deleteFavorite")
				continue
			}
			favoritesTable.removeValue(forKey: f.name)
			lookupTable[f.text] = (lookupTable[f.text] ?? []).filter{ $0 !== f }
			allGroup.remove(f)
			for g in Array(f.groups) {
				g.remove(f)
			}
		}
		save()
	}

	@discardableResult func newGroup(name: String = "") -> FavoritesGroup {
		var name = name.trimmingCharacters(in: .whitespaces)
		if name.isEmpty {
			name = "Group"
		}
		if groupTable[name] != nil {
			let root = name
			for i in 1... {
				name = "\(root) \(i)"
				if groupTable[name] == nil {
					break
				}
			}
		}
		let g = FavoritesGroup(profile: self, name: name)
		groupList.append(g)
		groupTable[name] = g
		save()
		return g
	}

	@discardableResult func renameGroup(_ g: FavoritesGroup, to: String) -> Bool {
		let to = to.trimmingCharacters(in: .whitespaces)
		guard !to.isEmpty else {
			return false
		}
		guard groupTable[to] == nil else {
			return false
		}
		guard groupTable[g.name] === g else {
			ServerProtocol.notifyAnomaly("Ignore unknown name (\(g.name)) in renameGroup")
			return false
		}
		groupTable.removeValue(forKey: g.name)
		g.name = to
		groupTable[to] = g
		save()
		return true
	}

	func deleteGroups(indices: IndexSet) {
		let deleted = indices.map{ index in groupList[index] }
		for d in deleted {
			groupTable.removeValue(forKey: d.name)
		}
		groupList.remove(atOffsets: indices)
		save()
	}

	func moveGroups(fromOffsets: IndexSet, toOffset: Int) {
		groupList.move(fromOffsets: fromOffsets, toOffset: toOffset)
		save()
	}

	func allGroups() -> [FavoritesGroup] {
		return Array(groupList)
	}

	func getGroup(_ name: String) -> FavoritesGroup? {
		groupTable[name]
	}
}
