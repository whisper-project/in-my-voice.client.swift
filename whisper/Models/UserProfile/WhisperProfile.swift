// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import CryptoKit

final class WhisperConversation: Conversation, Encodable, Decodable {
	private(set) var id: String
	fileprivate(set) var name: String = ""
	fileprivate(set) var allowed: [String: String] = [:]	// profile ID to username mapping

	fileprivate init(uuid: String? = nil) {
		self.id = uuid ?? UUID().uuidString
	}

	// lexicographic ordering by name
	// since two conversations can have the same name, we fall back
	// to lexicographic ID order to break ties with stability.
	static func <(_ left: WhisperConversation, _ right: WhisperConversation) -> Bool {
		if left.name == right.name {
			return left.id < right.id
		} else {
			return left.name < right.name
		}
	}
}


struct ListenerInfo: Identifiable {
	let id: String
	let username: String
}

final class WhisperProfile: Codable {
	var id: String
	private var table: [String: WhisperConversation]
	private var defaultId: String
	private var timestamp: Date
	private var serverPassword: String = ""

	private enum CodingKeys: String, CodingKey {
		case id, table, defaultId, timestamp
	}

	init(_ profileId: String) {
		id = profileId
		table = [:]
		defaultId = "none"
		timestamp = Date.now
	}

	var fallback: WhisperConversation {
		get {
			return ensureDefault()
		}
		set(c) {
			guard c.id != defaultId else {
				// nothing to do
				return
			}
			guard let existing = table[c.id] else {
				fatalError("Tried to set default whisper conversation to one not in whisper table")
			}
			defaultId = existing.id
			timestamp = Date.now
			save()
		}
	}

	// make sure there is a default conversation, and return it
	@discardableResult private func ensureDefault() -> WhisperConversation {
		if let c = table[defaultId] {
			return c
		} else if let firstC = table.first?.value {
			defaultId = firstC.id
			save()
			return firstC
		} else {
			let newC = newInternal()
			defaultId = newC.id
			save()
			return newC
		}
	}

	private func newInternal() -> WhisperConversation {
		let new = WhisperConversation()
		new.name = "Conversation \(table.count + 1)"
		logger.info("Adding whisper conversation \(new.id) (\(new.name))")
		table[new.id] = new
		return new
	}

	func conversations() -> [WhisperConversation] {
		ensureDefault()
		let sorted = Array(table.values).sorted()
		return sorted
	}

	/// Create a new whisper conversation
	@discardableResult func new() -> WhisperConversation {
		let c = newInternal()
		save()
		return c
	}

	/// Change the name of a conversation
	func rename(_ conversation: WhisperConversation, name: String) {
		guard let c = table[conversation.id] else {
			fatalError("Not a Whisper conversation: \(conversation.id)")
		}
		c.name = name
		save()
	}

	/// add a user to a conversation
	func addListener(_ conversation: WhisperConversation, info: WhisperProtocol.ClientInfo) {
		if let username = conversation.allowed[info.profileId], username == info.username {
			// nothing to do
			return
		}
		conversation.allowed[info.profileId] = info.username
		save()
	}

	/// find out whether a user has been added to a whisper conversation
	func isListener(_ conversation: WhisperConversation, info: WhisperProtocol.ClientInfo) -> ListenerInfo? {
		guard let username = conversation.allowed[info.profileId] else {
			return nil
		}
		return ListenerInfo(id: info.profileId, username: username)
	}

	/// remove user from a whisper conversation
	func removeListener(_ conversation: WhisperConversation, profileId: String) {
		if conversation.allowed.removeValue(forKey: profileId) != nil {
			save()
		}
	}

	/// list listeners for a whisper conversation
	func listeners(_ conversation: WhisperConversation) -> [ListenerInfo] {
		conversation.allowed.map({ k, v in ListenerInfo(id: k, username: v) })
	}

	/// Remove a conversation
	func delete(_ conversation: WhisperConversation) {
		logger.info("Removing whisper conversation \(conversation.id) (\(conversation.name))")
		if table.removeValue(forKey: conversation.id) != nil {
			if (defaultId == conversation.id) {
				ensureDefault()
			} else {
				save()
			}
		}
	}

	private func save(verb: String = "PUT", localOnly: Bool = false) {
		if !localOnly {
			timestamp = Date.now
		}
		guard let data = try? JSONEncoder().encode(self) else {
			fatalError("Cannot encode whisper profile: \(self)")
		}
		guard data.saveJsonToDocumentsDirectory("WhisperProfile") else {
			fatalError("Cannot save whisper profile to Documents directory")
		}
		if !localOnly && !serverPassword.isEmpty {
			saveToServer(data: data, verb: verb)
		}
	}

	static func load(_ profileId: String, serverPassword: String) -> WhisperProfile? {
		if let data = Data.loadJsonFromDocumentsDirectory("WhisperProfile"),
		   let profile = try? JSONDecoder().decode(WhisperProfile.self, from: data)
		{
			if profileId == profile.id {
				profile.serverPassword = serverPassword
				return profile
			}
			logger.warning("Asked to load profile with id \(profileId), deleting saved profile with id \(profile.id)")
			Data.removeJsonFromDocumentsDirectory("WhisperProfile")
		}
		return nil
	}

	private func saveToServer(data: Data, verb: String = "PUT") {
		let path = "/api/v2/whisperProfile" + (verb == "PUT" ? "/\(id)" : "")
		guard let url = URL(string: PreferenceData.whisperServer + path) else {
			fatalError("Can't create URL for whisper profile upload")
		}
		var request = URLRequest(url: url)
		request.httpMethod = verb
		request.setValue("Bearer \(serverPassword)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = data
		Data.executeJSONRequest(request)
	}

	func update(_ completionHandler: ((Bool) -> Void)? = nil) {
		guard !serverPassword.isEmpty else {
			// not a shared profile, so no way to update
			return
		}
		func handler(_ code: Int, _ data: Data) {
			if code < 200 || code > 300 {
				completionHandler?(false)
			} else if let profile = try? JSONDecoder().decode(WhisperProfile.self, from: data)
			{
				self.table = profile.table
				self.defaultId = profile.defaultId
				self.timestamp = profile.timestamp
				save(localOnly: true)
				completionHandler?(true)
			} else {
				completionHandler?(false)
			}
		}
		let path = "/api/v2/whisperProfile/\(id)"
		guard let url = URL(string: PreferenceData.whisperServer + path) else {
			fatalError("Can't create URL for whisper profile download")
		}
		var request = URLRequest(url: url)
		request.setValue("Bearer \(serverPassword)", forHTTPHeaderField: "Authorization")
		request.httpMethod = "GET"
		Data.executeJSONRequest(request)
	}

	func stopSharing() {
		// reset the profile
		id = UUID().uuidString
		serverPassword = ""
		table = [:]
		defaultId = "none"
		timestamp = Date.now
		save()
	}

	func startSharing(serverPassword: String) {
		self.serverPassword = serverPassword
		save(verb: "POST")
	}

	func loadShared(id: String, serverPassword: String, completionHandler: @escaping (Int) -> Void) {
		func handler(_ code: Int, _ data: Data) {
			if code < 200 || code > 300 {
				completionHandler(code)
			} else if let profile = try? JSONDecoder().decode(WhisperProfile.self, from: data)
			{
				self.id = id
				self.serverPassword = serverPassword
				self.table = profile.table
				self.defaultId = profile.defaultId
				self.timestamp = profile.timestamp
				save(localOnly: true)
				completionHandler(200)
			} else {
				completionHandler(-1)
			}
		}
		let path = "/api/v2/userProfile/\(id)"
		guard let url = URL(string: PreferenceData.whisperServer + path) else {
			fatalError("Can't create URL for whisper profile download")
		}
		var request = URLRequest(url: url)
		request.setValue("Bearer \(serverPassword)", forHTTPHeaderField: "Authorization")
		request.httpMethod = "GET"
		Data.executeJSONRequest(request, handler: handler)
	}
}
