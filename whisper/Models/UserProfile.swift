// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation

final class Conversation: Encodable, Decodable, Identifiable, Comparable, Equatable {
    private(set) var id: String
    var name: String
    
    fileprivate init(name: String) {
        self.id = UUID().uuidString
        self.name = name
    }
    
    fileprivate convenience init(from: Conversation) {
        self.init(name: from.name)
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
}

final class UserProfile: Encodable, Decodable, Identifiable, Equatable {
    static private(set) var shared = loadDefault() ?? createAndSaveDefault()
    
    private(set) var id: String
    var username: String = ""
    private var cTable: [String: Conversation] = [:]
    private var defaultId: String = ""
    
    init(username: String) {
        id = UUID().uuidString
        self.username = username
        ensureWellFormed()
    }
    
    init(from: UserProfile) {
        id = UUID().uuidString
        username = from.username
        for (id, c) in from.cTable {
            cTable[id] = Conversation(from: c)
        }
        defaultId = from.defaultId
    }
    
    private func ensureWellFormed() {
        guard let first = cTable.first?.value else {
            let first = Conversation(name: "My Conversation")
            cTable[first.id] = first
            defaultId = first.id
            return
        }
        if cTable[defaultId] == nil {
            defaultId = first.id
        }
    }
    
    var conversations: [Conversation] {
        get {
            ensureWellFormed()
            let random = Array(cTable.values)
            let sorted = random.sorted()
            return sorted
        }
    }
    
    var defaultConversation: Conversation {
        get {
            ensureWellFormed()
            return cTable[defaultId]!
        }
        set(new) {
            guard cTable[new.id] != nil else {
                // ignore the set, make sure there is a default
                ensureWellFormed()
                return
            }
            defaultId = new.id
        }
    }
    
    /// add a new conversation to the profile
    func newConversation() {
        ensureWellFormed()
        let new = Conversation(name: "Conversation \(cTable.count + 1)")
        cTable[new.id] = new
    }
    
    /// add a received conversation to the profile
    func addConversation(_ c: Conversation) {
        ensureWellFormed()
        cTable[c.id] = c
    }
    
    func deleteConversation(_ c: Conversation) {
        cTable.removeValue(forKey: c.id)
        ensureWellFormed()
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
            logger.info("Read default profile containing \(profile.cTable.count) conversation(s)")
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
            logger.info("Wrote default profile containing \(self.cTable.count) conversation(s)")
        }
        catch (let err) {
            logger.error("Failure to write default profile: \(err)")
            fatalError("Failure to write default profile: \(err)")
        }
    }
}
