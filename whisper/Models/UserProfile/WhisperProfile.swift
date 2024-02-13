// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation

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

final class WhisperProfile: Encodable, Decodable {
	var id: String
	private var table: [String: WhisperConversation]
	private var defaultId: String
	private var timestamp: Date
	private var shared: Bool

	init(_ profileId: String) {
		id = profileId
		table = [:]
		defaultId = "none"
		timestamp = Date.now
		shared = false
	}

	func updateFrom(_ profile: WhisperProfile) {
		id = profile.id
		table = profile.table
		defaultId = profile.defaultId
		timestamp = profile.timestamp
	}

	var isShared: Bool {
		get {
			return shared
		}
		set(val) {
			guard shared != val else {
				return
			}
			shared = val
			save()
		}
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

	private func save() {
		timestamp = Date.now
		guard let data = try? JSONEncoder().encode(self) else {
			fatalError("Cannot encode whisper profile: \(self)")
		}
		guard data.saveJsonToDocumentsDirectory("WhisperProfile") else {
			fatalError("Cannot save whisper profile to Documents directory")
		}
		if shared {
			saveToServer(data: data)
		}
	}

	static func load(_ profileId: String) -> WhisperProfile? {
		if let data = Data.loadJsonFromDocumentsDirectory("WhisperProfile"),
		   let profile = try? JSONDecoder().decode(WhisperProfile.self, from: data)
		{
			if profile.id != profileId {
				logger.warning("Overriding id \(profile.id) with id \(profileId) in loaded whisper profile")
				profile.id = profileId
				profile.save()
			}
			return profile
		}
		return nil
	}

	private func saveToServer(data: Data) {
		guard let url = URL(string: PreferenceData.whisperServer + "/api/v2/whisperProfile/\(id)") else {
			fatalError("Can't create URL for whisper profile upload")
		}
		var request = URLRequest(url: url)
		request.httpMethod = "PUT"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = data
		let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
			guard error == nil else {
				logger.error("Failed to post whisper profile: \(String(describing: error))")
				return
			}
			guard let response = response as? HTTPURLResponse else {
				logger.error("Received non-HTTP response on whisper profile post: \(String(describing: response))")
				return
			}
			if response.statusCode == 204 {
				logger.info("Successful post of whisper profile")
				return
			}
			logger.error("Received unexpected response on whisper profile post: \(response.statusCode)")
			guard let data = data,
				  let body = try? JSONSerialization.jsonObject(with: data),
				  let obj = body as? [String:String] else {
				logger.error("Can't deserialize whisper profile post response body: \(String(describing: data))")
				return
			}
			logger.error("Response body of whisper profile post: \(obj)")
		}
		logger.info("Posting whisper profile to whisper-server")
		task.resume()
	}
}
