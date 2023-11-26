// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation

final class Conversation: Encodable, Decodable, Identifiable, Comparable, Equatable {
    private(set) var id: String
    var name: String
    var allowedProfileIDs: [String] = []
    var lastListened: Date = Date.distantPast

    fileprivate init(name: String) {
        self.id = UUID().uuidString
        self.name = name
    }
    
    fileprivate convenience init(from: Conversation) {
        self.init(name: from.name)
        self.allowedProfileIDs = Array(from.allowedProfileIDs)
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
        }
        return left.name < right.name
    }
    
    // decreasing sort by last-used date then increasing sort by name within date bucket
    static func most_recent(_ left: Conversation, _ right: Conversation) -> Bool {
        if left.lastListened == right.lastListened {
            return left < right
        } else {
            return left.lastListened < right.lastListened
        }
    }
}

final class UserProfile: Encodable, Decodable, Identifiable, Equatable {
    static private(set) var shared = loadDefault() ?? createAndSaveDefault()
    
    private(set) var id: String
    var username: String = ""
    private var whisperTable: [String: Conversation] = [:]
    private var listenTable: [String: Conversation] = [:]
    private var defaultId: String = ""
    
    init(username: String) {
        id = UUID().uuidString
        self.username = username
    }
    
    init(from: UserProfile) {
        id = UUID().uuidString
        username = from.username
        for (id, c) in from.whisperTable {
            whisperTable[id] = Conversation(from: c)
        }
        defaultId = from.defaultId
    }
    
    // make sure there is a default conversation, and return it
    private func ensureWhisperDefaultExists() -> Conversation {
        if let firstC = whisperTable.first?.value {
            if let c = whisperTable[defaultId] {
                return c
            } else {
                defaultId = firstC.id
                return firstC
            }
        } else {
            let newC = addWhisperConversationInternal()
            defaultId = newC.id
            return newC
        }
    }
    
    /// The default whisper conversation
    var whisperDefault: Conversation {
        get {
            return ensureWhisperDefaultExists()
        }
        set(new) {
            if let existing = whisperTable[new.id]  {
                defaultId = existing.id
            }
        }
    }
    
    /// The sorted list of whisper conversations
    func whisperConversations() -> [Conversation] {
        _ = ensureWhisperDefaultExists()
        let sorted = Array(whisperTable.values).sorted()
        return sorted
    }
    
    /// The sorted list of listen conversations
    func listenConversations() -> [Conversation] {
        let sorted = Array(listenTable.values).sorted(by: Conversation.most_recent)
        return sorted
    }
    
    func addWhisperConversationInternal() -> Conversation {
        var prefix = "\(username)'s "
        if username.isEmpty {
            prefix = ""
        } else if username.hasSuffix("s") {
            prefix = "\(username)' "
        }
        let new = Conversation(name: "\(prefix)Conversation \(whisperTable.count + 1)")
        logger.info("Adding whisper conversation \(new.id) (\(new.name))")
        whisperTable[new.id] = new
        return new
    }
    
    /// Create a new whisper conversation
    func addWhisperConversation() {
        _ = addWhisperConversationInternal()
    }
    
    /// Add a newly used conversation for a Listener
    func addListenConversation(_ c: Conversation) {
        logger.info("Adding listen conversation \(c.id) (\(c.name))")
        listenTable[c.id] = c
        c.lastListened = Date.now
    }
    
    func deleteWhisperConversation(_ c: Conversation) {
        logger.info("Removing whisper conversation \(c.id) (\(c.name))")
        whisperTable.removeValue(forKey: c.id)
        _ = ensureWhisperDefaultExists()
    }
    
    func deleteListenConversation(_ c: Conversation) {
        logger.info("Removing listener conversation \(c.id) (\(c.name))")
        listenTable.removeValue(forKey: c.id)
    }
    
    // equality is determined by ID
    static func ==(_ left: UserProfile, _ right: UserProfile) -> Bool {
        return left.id == right.id
    }
    
    static func createAndSaveDefault() -> UserProfile {
        let profile = UserProfile(username: "")
        profile.saveAsDefault()
        return profile
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
    
    func saveAsDefault() {
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
