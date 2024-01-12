// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation

final class Conversation: Encodable, Decodable, Identifiable, Comparable, Equatable {
    private(set) var id: String
	fileprivate(set) var name: String = ""
	fileprivate(set) var owner: String = ""
	fileprivate(set) var ownerName: String = ""
	fileprivate(set) var allowed: [String: String] = [:]	// profile ID to username mapping
    fileprivate(set) var lastListened: Date = Date.distantPast
	var authorized: Bool { get { lastListened != Date.distantPast } }

	fileprivate init(uuid: String? = nil) {
        self.id = uuid ?? UUID().uuidString
    }
    
    // equality is determined by ID
    static func ==(_ left: Conversation, right: Conversation) -> Bool {
        return left.id == right.id
    }
    
    // lexicographic ordering by name
    // since two conversations can have the same name, we fall back
    // to lexicographic ID order to break ties with stability.
    static func <(_ left: Conversation, _ right: Conversation) -> Bool {
        if left.name == right.name {
            return left.id < right.id
		} else {
			return left.name < right.name
		}
    }
    
    // decreasing sort by last-used date then increasing sort by name within date bucket
    static func most_recent(_ left: Conversation, _ right: Conversation) -> Bool {
        if left.lastListened == right.lastListened {
            return left < right
        } else {
            return left.lastListened > right.lastListened
        }
    }
}

final class UserProfile: Encodable, Decodable, Identifiable, Equatable {
	struct ListenerInfo: Identifiable {
		let id: String
		let username: String
	}

    static private(set) var shared = loadDefault() ?? createAndSaveDefault()
    
    private(set) var id: String
	private(set) var name: String = ""
    private var whisperTable: [String: Conversation] = [:]
    private var listenTable: [String: Conversation] = [:]
    private var defaultId: String = ""
	private var timestamp: Date = Date.now

    private init() {
        id = UUID().uuidString
    }
    
	private func addWhisperConversationInternal() -> Conversation {
		let new = Conversation()
		new.name = "Conversation \(whisperTable.count + 1)"
		new.owner = id
		new.ownerName = name
		logger.info("Adding whisper conversation \(new.id) (\(new.name))")
		whisperTable[new.id] = new
		return new
	}

	var username: String {
		get { name }
		set(newName) { 
			guard name != newName else {
				// nothing to do
				return
			}
			name = newName
			saveAsDefault()
		}
	}

	// make sure there is a default conversation, and return it
	@discardableResult private func ensureWhisperDefaultExists() -> Conversation {
        if let firstC = whisperTable.first?.value {
            if let c = whisperTable[defaultId] {
                return c
            } else {
                defaultId = firstC.id
				saveAsDefault()
                return firstC
            }
        } else {
            let newC = addWhisperConversationInternal()
            defaultId = newC.id
			saveAsDefault()
            return newC
        }
    }
    
    /// The default whisper conversation
    var whisperDefault: Conversation {
        get {
            return ensureWhisperDefaultExists()
        }
        set(new) {
			guard new.id != defaultId else {
				// nothing to do
				return
			}
            guard let existing = whisperTable[new.id] else {
				fatalError("Tried to set default whisper conversation to one not in whisper table")
			}
			defaultId = existing.id
			saveAsDefault()
        }
    }
    
    /// The sorted list of whisper conversations
    func whisperConversations() -> [Conversation] {
        ensureWhisperDefaultExists()
        let sorted = Array(whisperTable.values).sorted()
        return sorted
    }
    
    /// The sorted list of listen conversations
    func listenConversations() -> [Conversation] {
        let sorted = Array(listenTable.values).sorted(by: Conversation.most_recent)
        return sorted
    }
    
    /// Create a new whisper conversation
    @discardableResult func addWhisperConversation() -> Conversation {
        let c = addWhisperConversationInternal()
		saveAsDefault()
		return c
    }

	/// Change the name of a whisper conversation
	func renameWhisperConversation(c: Conversation, name: String) {
		guard let c = whisperTable[c.id] else {
			fatalError("Not a Whisper conversation: \(c.id)")
		}
		c.name = name
		saveAsDefault()
	}

	/// add a user to a whisper conversation
	func addListenerToWhisperConversation(info: WhisperProtocol.ClientInfo, conversation: Conversation) {
		if let username = conversation.allowed[info.profileId], username == info.username {
			// nothing to do
			return
		}
		conversation.allowed[info.profileId] = info.username
		saveAsDefault()
	}

	/// find out whether a user has been added to a whisper conversation
	func isListenerToWhisperConversation(info: WhisperProtocol.ClientInfo, conversation: Conversation) -> ListenerInfo? {
		guard let username = conversation.allowed[info.profileId] else {
			return nil
		}
		return ListenerInfo(id: info.profileId, username: username)
	}

	/// remove user from a whisper conversation
	func removeListenerFromWhisperConversation(profileId: String, conversation: Conversation) {
		if conversation.allowed.removeValue(forKey: profileId) != nil {
			saveAsDefault()
		}
	}

	/// list listeners for a whisper conversation
	func listenersToWhisperConversation(conversation: Conversation) -> [ListenerInfo] {
		conversation.allowed.map({ k, v in ListenerInfo(id: k, username: v) })
	}

	/// get a listen conversation from a web link conversation ID
	func listenConversationForLink(_ id: String) -> Conversation {
		if let existing = listenTable[id] {
			return existing
		} else {
			return Conversation(uuid: id)
		}
	}

	/// get a listen conversation for an whisperer's invite
	func listenConversationForInvite(info: WhisperProtocol.ClientInfo) -> Conversation {
		let c = listenTable[info.conversationId] ?? Conversation(uuid: info.conversationId)
		c.name = info.conversationName
		c.owner = info.profileId
		c.ownerName = info.username
		return c
	}

    /// Add a newly used conversation for a Listener
	func addListenConversationForInvite(info: WhisperProtocol.ClientInfo) -> Conversation {
        let c = listenConversationForInvite(info: info)
		listenTable[c.id] = c
        c.lastListened = Date.now
		return c
    }

	/// Remove a conversation
    func deleteWhisperConversation(_ c: Conversation) {
        logger.info("Removing whisper conversation \(c.id) (\(c.name))")
		if whisperTable.removeValue(forKey: c.id) != nil {
			saveAsDefault()
		}
		ensureWhisperDefaultExists()
    }
    
    func deleteListenConversation(_ id: String) {
        logger.info("Removing listener conversation \(id)")
		if listenTable.removeValue(forKey: id) != nil {
			saveAsDefault()
		}
    }
    
    // equality is determined by ID
    static func ==(_ left: UserProfile, _ right: UserProfile) -> Bool {
        return left.id == right.id
    }
    
    static func loadDefault() -> UserProfile? {
        do {
            let folderURL = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            let fileUrl = folderURL.appendingPathComponent("defaultProfile.json")
            let data = try Data(contentsOf: fileUrl)
            let decoder = JSONDecoder()
            let profile = try decoder.decode(UserProfile.self, from: data)
            logger.info("Read default profile containing \(profile.whisperTable.count) whisper and \(profile.listenTable.count) listen conversation(s)")
            return profile
        }
        catch (let err) {
            logger.error("Failure reading default profile: \(err)")
            return nil
        }
    }
    
	private static func createAndSaveDefault() -> UserProfile {
		let profile = UserProfile()
		profile.saveAsDefault()
		return profile
	}

    private func saveAsDefault() {
		timestamp = Date.now
        do {
            let folderURL = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            let fileUrl = folderURL.appendingPathComponent("defaultProfile.json")
            let encoder = JSONEncoder()
            let data = try encoder.encode(self)
            try data.write(to: fileUrl)
            logger.info("Wrote default profile containing \(self.whisperTable.count) whisper and \(self.listenTable.count) listen conversation(s)")
        }
        catch (let err) {
            logger.error("Failure to write default profile: \(err)")
            fatalError("Failure to write default profile: \(err)")
        }
    }
}
