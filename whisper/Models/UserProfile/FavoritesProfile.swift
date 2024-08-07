// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation

fileprivate let allTag = "All"

fileprivate struct StoredProfile: Codable {
	var id: String
	var timestamp: Int
	var favorites: [Favorite]
	var tags: [String: [String]]
}

final class Favorite: Comparable, Codable {
	fileprivate(set) var name: String
	fileprivate(set) var text: String
	fileprivate var speechHash: Int?
	fileprivate var speechId: String?

	fileprivate init(name: String, text: String) {
		self.name = name
		self.text = text
	}

	// depends on there never being two favorites with the same name
	static func == (lhs: Favorite, rhs: Favorite) -> Bool {
		lhs.name == rhs.name
	}

	// depends on there never being two favorites with the same name
	static func < (lhs: Favorite, rhs: Favorite) -> Bool {
		lhs.name < rhs.name
	}
}

final class TagSet: Comparable {
	private var profile: FavoritesProfile
	fileprivate(set) var tag: String
	private(set) var favorites: [Favorite] = []
	private var favoriteNames: Set<String> = Set()

	fileprivate init(profile: FavoritesProfile, tag: String) {
		self.profile = profile
		self.tag = tag
	}

	// depends on there never being two tag sets with the same name
	static func == (lhs: TagSet, rhs: TagSet) -> Bool {
		lhs.tag == rhs.tag
	}


	// depends on there never being two tag sets with the same name
	static func < (lhs: TagSet, rhs: TagSet) -> Bool {
		lhs.tag < rhs.tag
	}

	func add(_ f: Favorite, at: Int? = nil) {
		guard !favoriteNames.contains(f.name) else {
			return
		}
		favoriteNames.insert(f.name)
		if let i = at, i >= 0, i < favorites.count {
			favorites.insert(f, at: i)
		} else {
			self.favorites.append(f)
		}
	}

	func move(fromOffsets: IndexSet, toOffset: Int) {
		favorites.move(fromOffsets: fromOffsets, toOffset: toOffset)
	}

	func onDelete(deleteOffsets: IndexSet) {
		let deleted = deleteOffsets.compactMap{ index in favorites[index] }
		guard tag != allTag else {
			// removing from the all set is a remove from the profile
			for d in deleted {
				profile.deleteFavorite(d)
			}
			return
		}
		favorites.remove(atOffsets: deleteOffsets)
		for d in deleted {
			favoriteNames.remove(d.name)
		}
	}

	func remove(_ f: Favorite) {
		favorites.removeAll(where: { f === $0 })
		favoriteNames.remove(f.name)
	}
}

final class FavoritesProfile: Codable {
	var id: String
	var timestamp: Int
	private var favoritesTable: [String: Favorite] = [:]
	private var allSet: TagSet! = nil
	private var tagSetTable: [String: TagSet] = [:]
	private var serverPassword: String = ""

	init(_ profileId: String) {
		id = profileId
		timestamp = Int(Date.now.timeIntervalSince1970)
		allSet = TagSet(profile: self, tag: allTag)
		tagSetTable = [allTag: allSet]
		save()
	}

	init(from: any Decoder) throws {
		let stored = try StoredProfile(from: from)
		id = stored.id
		timestamp = stored.timestamp
		favoritesTable = [:]
		allSet = TagSet(profile: self, tag: allTag)
		tagSetTable = [allTag: allSet]
		var allFound = false
		for f in stored.favorites {
			favoritesTable[f.name] = f
		}
		for (t, ns) in stored.tags {
			var ts: TagSet
			if t == allTag {
				ts = allSet
				allFound = true
			} else {
				ts = TagSet(profile: self, tag: t)
				tagSetTable[t] = ts
			}
			for n in ns {
				if let f = favoritesTable[n] {
					ts.add(f)
				}
			}
		}
		if !allFound {
			let message = "Stored favorites must contain an \(allTag) tag"
			logAnomaly(message)
			throw message
		}
	}

	func encode(to: any Encoder) throws {
		let favorites = Array(favoritesTable.values)
		let tags = tagSetTable.mapValues{ ts in ts.favorites.map{ f in f.name} }
		let stored = StoredProfile(id: id, timestamp: timestamp, favorites: favorites, tags: tags)
		try stored.encode(to: to)
	}

	@discardableResult func newFavorite(text: String, name: String = "", tags: [String] = []) -> Favorite {
		var name = name.trimmingCharacters(in: .whitespaces)
		if name.isEmpty {
			name = "Favorite"
		}
		if favoritesTable[name] != nil {
			let root = name
			for i in [1...] {
				name = "\(root) \(i)"
				if favoritesTable[name] == nil {
					break
				}
			}
		}
		let f = Favorite(name: name, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
		favoritesTable[name] = f
		allSet.add(f)
		for tag in tags {
			if tag == allTag {
				continue
			}
			if let tagSet = tagSetTable[tag] {
				tagSet.add(f)
			} else {
				logAnomaly("Ignoring unknown tag (\(tag)) in newFavorite(\(name))")
			}
		}
		save()
		return f
	}

	func renameFavorite(_ f: Favorite, to: String) -> Bool {
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

	func deleteFavorite(_ f: Favorite) {
		guard f === favoritesTable[f.name] else {
			logAnomaly("Ignoring unknown favorite \(f.name) in deleteFavorite")
			return
		}
		favoritesTable.removeValue(forKey: f.name)
		allSet.remove(f)
		for ts in tagSetTable.values {
			if ts === allSet {
				continue
			}
			ts.remove(f)
		}
		save()
	}

	@discardableResult func newTagSet(name: String = "") -> TagSet {
		var name = name.trimmingCharacters(in: .whitespaces)
		if name.isEmpty {
			name = "Tag"
		}
		if tagSetTable[name] != nil {
			let root = name
			for i in [1...] {
				name = "\(root) \(i)"
				if tagSetTable[name] == nil {
					break
				}
			}
		}
		let ts = TagSet(profile: self, tag: name)
		tagSetTable[name] = ts
		save()
		return ts
	}

	func renameTagSet(_ ts: TagSet, to: String) -> Bool {
		let to = to.trimmingCharacters(in: .whitespaces)
		guard tagSetTable[to] == nil else {
			return false
		}
		guard tagSetTable[ts.tag] === ts else {
			logAnomaly("Ignore unknown tag (\(ts.tag)) in renameTagSet")
			return false
		}
		tagSetTable.removeValue(forKey: ts.tag)
		ts.tag = to
		tagSetTable[to] = ts
		save()
		return true
	}

	func deleteTagSet(_ ts: TagSet) -> Bool {
		guard ts.tag != allTag else {
			return false
		}
		guard tagSetTable[ts.tag] === ts else {
			logAnomaly("Ignore unknown tag (\(ts.tag)) in deleteTagSet")
			return false
		}
		tagSetTable.removeValue(forKey: ts.tag)
		save()
		return true
	}

	func allTags() -> [TagSet] {
		return Array(tagSetTable.values).sorted()
	}

	private func save(verb: String = "PUT", localOnly: Bool = false) {
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
					self.favoritesTable = profile.favoritesTable
					self.allSet = profile.allSet
					self.tagSetTable = profile.tagSetTable
					self.timestamp = profile.timestamp
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
				self.favoritesTable = profile.favoritesTable
				self.allSet = profile.allSet
				self.tagSetTable = profile.tagSetTable
				self.timestamp = profile.timestamp
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
