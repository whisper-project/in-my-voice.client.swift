// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine

protocol Conversation: Identifiable, Equatable, Comparable {
	var id: String { get }
	var name: String { get }
}

extension Conversation {
	static func ==(_ left: Self, _ right: Self) -> Bool {
		return left.id == right.id
	}
}

final class UserProfile: Identifiable {
	static private(set) var shared = load() ?? create()

	private(set) var id: String
	private(set) var name: String = ""
    private(set) var whisperProfile: WhisperProfile
	private(set) var listenProfile: ListenProfile

	private init() {
        id = UUID().uuidString
		whisperProfile = WhisperProfile(id)
		listenProfile = ListenProfile(id)
    }

	private init(id: String, name: String) {
		self.id = id
		self.name = name
		self.whisperProfile = WhisperProfile.load(id) ?? WhisperProfile(id)
		self.listenProfile = ListenProfile.load(id) ?? ListenProfile(id)
	}

	var username: String {
		get { name }
		set(newName) { 
			guard name != newName else {
				// nothing to do
				return
			}
			name = newName
			save()
		}
	}

	private func save() {
		let value = ["id": id, "name": name]
		guard let data = try? JSONSerialization.data(withJSONObject: value) else {
			fatalError("Can't encode user profile data: \(value)")
		}
		guard data.saveJsonToDocumentsDirectory("UserProfile") else {
			fatalError("Can't save user profile data")
		}
		// TODO: if shared, update server
	}

	func update() {
		// TODO: check with server for updates
	}

	static private func load() -> UserProfile? {
		if let data = Data.loadJsonFromDocumentsDirectory("UserProfile"),
		   let obj = try? JSONSerialization.jsonObject(with: data),
		   let value = obj as? [String:String],
		   let id = value["id"],
		   let name = value["name"]
		{
			return UserProfile(id: id, name: name)
		}
		return nil
    }

	private static func create() -> UserProfile {
		let profile = UserProfile()
		profile.save()
		return profile
	}
}
