// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation

fileprivate struct StoredProfile: Codable {
	var id: String
	var timestamp: Int
	var favorites: [Favorite]
	var groupList: [String]
	var groupTable: [String: [String]]
}

final class Favorite: Identifiable, Comparable, Hashable, Codable {
	fileprivate(set) var profile: FavoritesProfile?
	fileprivate(set) var name: String
	fileprivate(set) var text: String
	fileprivate(set) var groups: Set<Group> = Set()
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

	func updateText(_ text: String) {
		let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty else {
			return
		}
		self.text = text
		self.speechId = nil
		self.speechHash = nil
		profile?.save()
	}

	func speakText() {
		speakTextInternal(regenerate: false)
	}

	func regenerateText() {
		speakTextInternal(regenerate: true)
	}

	private func speakTextInternal(regenerate: Bool) {
		let memoize: TransportSuccessCallback = { result in
			if result == nil, let item = ElevenLabs.shared.lookupText(self.text) {
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
		ElevenLabs.shared.speakText(text: text, successCallback: memoize)
	}
}

final class Group: Identifiable, Hashable {
	fileprivate var profile: FavoritesProfile
	fileprivate(set) var name: String
	private(set) var favorites: [Favorite] = []
	private var favoriteNames: Set<String> = Set()

	fileprivate init(profile: FavoritesProfile, name: String) {
		self.profile = profile
		self.name = name
	}

	static func == (lhs: Group, rhs: Group) -> Bool {
		lhs === rhs
	}

	func hash(into hasher: inout Hasher) {
		name.hash(into: &hasher)
	}

	var id: String {
		get { self.name }
	}

	func add(_ f: Favorite) {
		addInternal(f)
		profile.save()
	}

	fileprivate func addInternal(_ f: Favorite, at: Int? = nil) {
		guard !favoriteNames.contains(f.name) else {
			return
		}
		favoriteNames.insert(f.name)
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
			favoriteNames.remove(d.name)
			d.groups.remove(self)
		}
		profile.save()
	}

	func remove(_ f: Favorite) {
		favorites.removeAll(where: { f === $0 })
		favoriteNames.remove(f.name)
		f.groups.remove(self)
		profile.save()
	}
}

final class FavoritesProfile: Codable {
	var id: String
	var timestamp: Int
	private var favoritesTable: [String: Favorite]
	private(set) var allGroup: Group! = nil
	private var groupTable: [String: Group]
	private var groupList: [Group] = []
	private var serverPassword: String = ""

	init(_ profileId: String) {
		id = profileId
		timestamp = Int(Date.now.timeIntervalSince1970)
		favoritesTable = [:]
		groupList = []
		groupTable = [:]
		allGroup = Group(profile: self, name: "")
		newFavorite(text: "This is a sample favorite.")
		save()
	}

	init(from: any Decoder) throws {
		let stored = try StoredProfile(from: from)
		id = stored.id
		timestamp = stored.timestamp
		favoritesTable = [:]
		groupList = []
		groupTable = [:]
		allGroup = Group(profile: self, name: "")
		for f in stored.favorites {
			f.profile = self
			favoritesTable[f.name] = f
			if let hash = f.speechHash, let id = f.speechId {
				logger.info("Favorite '\(f.name, privacy: .public)' has speech ID \(id, privacy: .public)")
				ElevenLabs.shared.memoizeText(f.text, hash: hash, id: id)
			}
			allGroup.addInternal(f)
		}
		for name in stored.groupList {
			let g = Group(profile: self, name: name)
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

	/// update the existing profile from a loaded server-side profile
	private func updateFromProfile(_ profile: FavoritesProfile) {
		self.favoritesTable = profile.favoritesTable
		self.allGroup = profile.allGroup
		for f in allGroup.favorites { f.profile = self }
		self.groupList = profile.groupList
		for g in self.groupList { g.profile = self }
		self.groupTable = profile.groupTable
		self.timestamp = profile.timestamp
	}

	func encode(to: any Encoder) throws {
		let favorites = Array(allGroup.favorites)
		let groupList = groupList.map{ $0.name }
		let groupTable = groupTable.mapValues{ g in g.favorites.map{ $0.name } }
		let stored = StoredProfile(
			id: id, timestamp: timestamp, favorites: favorites, groupList: groupList, groupTable: groupTable
		)
		try stored.encode(to: to)
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
		let f = Favorite(profile: self, name: name, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
		favoritesTable[name] = f
		allGroup.add(f)
		for name in tags {
			if let tagSet = groupTable[name] {
				tagSet.addInternal(f)
			} else {
				logAnomaly("Ignoring unknown name (\(name)) in newFavorite(\(name))")
			}
		}
		save()
		return f
	}

	@discardableResult func renameFavorite(_ f: Favorite, to: String) -> Bool {
		let to = to.trimmingCharacters(in: .whitespaces)
		guard favoritesTable[to] == nil else {
			return false
		}
		guard favoritesTable[f.name] === f else {
			logAnomaly("Ignore unknown favorite (\(f.name)) in renameFavorite")
			return false
		}
		favoritesTable.removeValue(forKey: f.name)
		f.name = to
		favoritesTable[to] = f
		save()
		return true
	}

	fileprivate func deleteFavorites(_ fs: [Favorite]) {
		for f in fs {
			guard f === favoritesTable[f.name] else {
				logAnomaly("Ignoring unknown favorite \(f.name) in deleteFavorite")
				continue
			}
			favoritesTable.removeValue(forKey: f.name)
			allGroup.remove(f)
			for g in Array(f.groups) {
				g.remove(f)
			}
		}
		save()
	}

	@discardableResult func newGroup(name: String = "") -> Group {
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
		let g = Group(profile: self, name: name)
		groupList.append(g)
		groupTable[name] = g
		save()
		return g
	}

	@discardableResult func renameGroup(_ g: Group, to: String) -> Bool {
		let to = to.trimmingCharacters(in: .whitespaces)
		guard !to.isEmpty else {
			return false
		}
		guard groupTable[to] == nil else {
			return false
		}
		guard groupTable[g.name] === g else {
			logAnomaly("Ignore unknown name (\(g.name)) in renameGroup")
			return false
		}
		groupTable.removeValue(forKey: g.name)
		g.name = to
		groupTable[to] = g
		save()
		return true
	}

	func deleteGroup(_ g: Group) {
		guard !g.name.isEmpty else {
			logAnomaly("Trying to delete a group with no name?")
			return
		}
		guard groupTable[g.name] === g else {
			logAnomaly("Ignore unknown name (\(g.name)) in deleteGroup")
			return
		}
		groupTable.removeValue(forKey: g.name)
		save()
	}

	func allGroups() -> [Group] {
		return Array(groupList)
	}

	func getGroup(_ name: String) -> Group? {
		groupTable[name]
	}

	fileprivate func save(verb: String = "PUT", localOnly: Bool = false) {
		if !localOnly {
			timestamp = Int(Date.now.timeIntervalSince1970)
		}
		guard let data = try? JSONEncoder().encode(self) else {
			fatalError("Cannot encode favorites profile: \(self)")
		}
		guard data.saveJsonToDocumentsDirectory("FavoritesProfile") else {
			fatalError("Cannot save favorites profile to Documents directory")
		}
		if !localOnly && !serverPassword.isEmpty {
			saveToServer(data: data, verb: verb)
		}
	}

	static func load(_ profileId: String, serverPassword: String) -> FavoritesProfile? {
		if let data = Data.loadJsonFromDocumentsDirectory("FavoritesProfile"),
		   let profile = try? JSONDecoder().decode(FavoritesProfile.self, from: data)
		{
			if profileId == profile.id {
				profile.serverPassword = serverPassword
				return profile
			}
			logger.warning("Asked to load profile with id \(profileId), deleting saved profile with id \(profile.id)")
			Data.removeJsonFromDocumentsDirectory("FavoritesProfile")
		}
		return nil
	}

	private func saveToServer(data: Data, verb: String = "PUT") {
		let path = "/api/v2/favoritesProfile" + (verb == "PUT" ? "/\(id)" : "")
		guard let url = URL(string: PreferenceData.whisperServer + path) else {
			fatalError("Can't create URL for favorites profile upload")
		}
		logger.info("\(verb) of favorites profile to server, current timestamp: \(self.timestamp)")
		var request = URLRequest(url: url)
		request.httpMethod = verb
		if verb == "PUT" {
			request.setValue("Bearer \(serverPassword)", forHTTPHeaderField: "Authorization")
		}
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue(PreferenceData.clientId, forHTTPHeaderField: "X-Client-Id")
		request.httpBody = data
		Data.executeJSONRequest(request)
	}

	func update(_ notifyChange: (() -> Void)? = nil) {
		guard !serverPassword.isEmpty else {
			// not a shared profile, so no way to update
			return
		}
		func handler(_ code: Int, _ data: Data) {
			if code == 200 {
				if let profile = try? JSONDecoder().decode(FavoritesProfile.self, from: data) {
					logger.info("Received updated favorites profile, timestamp is \(profile.timestamp)")
					self.updateFromProfile(profile)
					save(localOnly: true)
					notifyChange?()
				} else {
					logAnomaly("Received invalid favorites profile data: \(String(decoding: data, as: UTF8.self))")
				}
			} else if code == 404 {
				// this is supposed to be a shared profile, but the server doesn't have it?!
				logAnomaly("Found no favorites profile on server when updating, uploading one")
				save(verb: "POST")
			}
		}
		let path = "/api/v2/favoritesProfile/\(id)"
		guard let url = URL(string: PreferenceData.whisperServer + path) else {
			fatalError("Can't create URL for favorites profile download")
		}
		var request = URLRequest(url: url)
		request.setValue("Bearer \(serverPassword)", forHTTPHeaderField: "Authorization")
		request.setValue("\"\(self.timestamp)\"", forHTTPHeaderField: "If-None-Match")
		request.setValue(PreferenceData.clientId, forHTTPHeaderField: "X-Client-Id")
		request.httpMethod = "GET"
		Data.executeJSONRequest(request, handler: handler)
	}

	func startSharing(serverPassword: String, ownConversations: [WhisperConversation] = []) {
		self.serverPassword = serverPassword
		save(verb: "POST")
	}

	func loadShared(id: String, serverPassword: String, completionHandler: @escaping (Int) -> Void) {
		func handler(_ code: Int, _ data: Data) {
			if code < 200 || code >= 300 {
				completionHandler(code)
			} else if let profile = try? JSONDecoder().decode(FavoritesProfile.self, from: data)
			{
				self.id = id
				self.serverPassword = serverPassword
				self.updateFromProfile(profile)
				save(localOnly: true)
				completionHandler(200)
			} else {
				logAnomaly("Received invalid favorites profile data: \(String(decoding: data, as: UTF8.self))")
				completionHandler(-1)
			}
		}
		let path = "/api/v2/favoritesProfile/\(id)"
		guard let url = URL(string: PreferenceData.whisperServer + path) else {
			fatalError("Can't create URL for favorites profile download")
		}
		var request = URLRequest(url: url)
		request.setValue("Bearer \(serverPassword)", forHTTPHeaderField: "Authorization")
		request.setValue(PreferenceData.clientId, forHTTPHeaderField: "X-Client-Id")
		request.setValue("\"  impossible-timestamp   \"", forHTTPHeaderField: "If-None-Match")
		request.httpMethod = "GET"
		Data.executeJSONRequest(request, handler: handler)
	}
}
