// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation

final class ListenConversation: Conversation, Encodable, Decodable {
	private(set) var id: String
	fileprivate(set) var name: String = ""
	fileprivate(set) var owner: String = ""
	fileprivate(set) var ownerName: String = ""
	fileprivate(set) var lastListened: Date = Date.distantPast

	var authorized: Bool { get { lastListened != Date.distantPast } }

	fileprivate init(uuid: String? = nil) {
		self.id = uuid ?? UUID().uuidString
	}

	// decreasing sort by last-used date then increasing sort by name within date bucket
	static func <(_ left: ListenConversation, _ right: ListenConversation) -> Bool {
		if left.lastListened == right.lastListened {
			return left < right
		} else {
			return left.lastListened > right.lastListened
		}
	}
}

final class ListenProfile: Encodable, Decodable {
	var id: String
	private var table: [String: ListenConversation]

	init(_ profileId: String) {
		id = profileId
		table = [:]
	}

	/// The sorted list of listen conversations
	func conversations() -> [ListenConversation] {
		let sorted = Array(table.values).sorted()
		return sorted
	}

	/// get a listen conversation from a web link conversation ID
	func fromLink(_ id: String) -> ListenConversation {
		if let existing = table[id] {
			return existing
		} else {
			return ListenConversation(uuid: id)
		}
	}

	/// get a listen conversation for a Whisperer's invite
	func forInvite(info: WhisperProtocol.ClientInfo) -> ListenConversation {
		if let c = table[info.conversationId] {
			var changed = false
			if !info.conversationName.isEmpty && info.conversationName != c.name {
				c.name = info.conversationName
				changed = true
			}
			if !info.profileId.isEmpty && info.profileId != c.owner {
				c.owner = info.profileId
				changed = true
			}
			if !info.username.isEmpty && info.username != c.ownerName {
				c.ownerName = info.username
				changed = true
			}
			if changed {
				save()
			}
			return c
		}
		let c =  ListenConversation(uuid: info.conversationId)
		c.name = info.conversationName
		c.owner = info.profileId
		c.ownerName = info.username
		return c
	}

	/// Add a newly used conversation for a Listener
	func addForInvite(info: WhisperProtocol.ClientInfo) -> ListenConversation {
		let c = forInvite(info: info)
		if table[c.id] == nil {
			logger.info("Adding new listen conversation")
			table[c.id] = c
		}
		c.lastListened = Date.now
		save()
		return c
	}

	func delete(_ id: String) {
		logger.info("Removing listen conversation \(id)")
		if table.removeValue(forKey: id) != nil {
			save()
		}
	}

	private func save() {
		guard let data = try? JSONEncoder().encode(self) else {
			fatalError("Cannot encode listen profile: \(self)")
		}
		guard data.saveJsonToDocumentsDirectory("ListenProfile") else {
			fatalError("Cannot save listen profile to Documents directory")
		}
	}

	static func load(_ profileId: String) -> ListenProfile? {
		if let data = Data.loadJsonFromDocumentsDirectory("ListenProfile"),
		   let profile = try? JSONDecoder().decode(ListenProfile.self, from: data)
		{
			if profile.id != profileId {
				logger.warning("Overriding id \(profile.id) with id \(profileId) in loaded listen profile")
				profile.id = profileId
				profile.save()
			}
			return profile
		}
		return nil
	}
}
