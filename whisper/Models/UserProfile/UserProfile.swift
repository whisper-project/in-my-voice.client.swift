// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine
import CryptoKit

protocol Conversation: Identifiable, Equatable, Comparable {
	var id: String { get }
	var name: String { get }
}

extension Conversation {
	static func ==(_ left: Self, _ right: Self) -> Bool {
		return left.id == right.id
	}
}

final class UserProfile: Identifiable, ObservableObject {
	static private(set) var shared = load() ?? create()

	@Published private(set) var id: String
	@Published private(set) var name: String = ""
	@Published private(set) var whisperProfile: WhisperProfile
	@Published private(set) var listenProfile: ListenProfile
	@Published private(set) var userPassword: String
	private var serverPassword: String

	private init() {
		let profileId = UUID().uuidString
		id = profileId
		userPassword = ""
		serverPassword = ""
		whisperProfile = WhisperProfile(profileId)
		listenProfile = ListenProfile(profileId)
	}

	private init(id: String, name: String, password: String) {
		self.id = id
		self.name = name
		userPassword = password
		serverPassword = SHA256.hash(data: Data(password.utf8)).compactMap{ String(format: "%02x", $0) }.joined()
		whisperProfile = WhisperProfile.load(id, serverPassword: serverPassword) ?? WhisperProfile(id)
		listenProfile = ListenProfile.load(id) ?? ListenProfile(id)
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

	private func save(verb: String = "PUT", localOnly: Bool = false) {
		let localValue = ["id": id, "name": name, "password": userPassword]
		guard let localData = try? JSONSerialization.data(withJSONObject: localValue) else {
			fatalError("Can't encode user profile data: \(localValue)")
		}
		guard localData.saveJsonToDocumentsDirectory("UserProfile") else {
			fatalError("Can't save user profile data")
		}
		if !localOnly && !serverPassword.isEmpty {
			let serverValue = ["id": id, "name": name, "password": serverPassword]
			guard let serverData = try? JSONSerialization.data(withJSONObject: serverValue) else {
				fatalError("Can't encode user profile data: \(serverValue)")
			}
			saveToServer(data: serverData, verb: verb)
		}
	}

	static private func load() -> UserProfile? {
		if let data = Data.loadJsonFromDocumentsDirectory("UserProfile"),
		   let obj = try? JSONSerialization.jsonObject(with: data),
		   let value = obj as? [String:String],
		   let id = value["id"],
		   let name = value["name"],
		   let password = value["password"]
		{
			return UserProfile(id: id, name: name, password: password)
		}
		return nil
	}

	private static func create() -> UserProfile {
		let profile = UserProfile()
		profile.save()
		return profile
	}

	private func saveToServer(data: Data, verb: String = "PUT") {
		let path = "/api/v2/userProfile" + (verb == "PUT" ? "/\(id)" : "")
		guard let url = URL(string: PreferenceData.whisperServer + path) else {
			fatalError("Can't create URL for user profile upload")
		}
		var request = URLRequest(url: url)
		request.httpMethod = verb
		request.setValue("Bearer \(serverPassword)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = data
		Data.executeJSONRequest(request)
	}

	func update() {
		func handler(_ code: Int, _ data: Data) {
			if code == 200,
			   let obj = try? JSONSerialization.jsonObject(with: data),
			   let value = obj as? [String:String],
			   let name = value["name"]
			{
				self.name = name
				save(localOnly: true)
			}
		}
		let path = "/api/v2/userProfile/\(id)"
		let token = SHA256.hash(data: Data(userPassword.utf8)).compactMap{ String(format: "%02x", $0) }.joined()
		guard let url = URL(string: PreferenceData.whisperServer + path) else {
			fatalError("Can't create URL for user profile download")
		}
		var request = URLRequest(url: url)
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.httpMethod = "GET"
		Data.executeJSONRequest(request, handler: handler)
		whisperProfile.update()
	}

	func stopSharing() {
		// reset the profile
		id = UUID().uuidString
		userPassword = ""
		whisperProfile = WhisperProfile(id)
		listenProfile = ListenProfile(id)
		save()
	}

	func startSharing() {
		// set the password, post the profile to server
		let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789~!@#$%_+-="
		userPassword = String((0..<20).map{ _ in letters.randomElement()! })
		save(verb: "POST")
		whisperProfile.startSharing(serverPassword: userPassword)
	}

	func receiveSharing(id: String, password: String, completionHandler: @escaping (Bool, String) -> Void) {
		// reset the profile and update from server
		loadShared(id: id, password: password, completionHandler: completionHandler)
	}

	func loadShared(id: String, password: String, completionHandler: @escaping (Bool, String) -> Void) {
		let serverPassword = SHA256.hash(data: Data(password.utf8)).compactMap{ String(format: "%02x", $0) }.joined()
		var doingNameUpdate = true
		var newName = name
		func dualHandler(_ result: Int) {
			switch result {
			case 200:
				if doingNameUpdate {
					doingNameUpdate = false
					whisperProfile.loadShared(id: id, serverPassword: serverPassword, completionHandler: dualHandler)
				} else {
					self.id = id
					self.name = newName
					self.userPassword = password
					self.serverPassword = serverPassword
					save(localOnly: true)
					completionHandler(true, "Profile received successfully")
				}
			case 403:
				completionHandler(false, "Incorrect password")
			case 404:
				completionHandler(false, "Unknown Profile ID")
			case -1:
				completionHandler(false, "Received invalid data from the whisper server")
			default:
				completionHandler(false, "Failed to retrieve profile: error code \(result)")
			}
		}
		func nameHandler(_ code: Int, _ data: Data) {
			if code < 200 || code >= 300 {
				dualHandler(code)
			} else if let obj = try? JSONSerialization.jsonObject(with: data),
					  let value = obj as? [String:String],
					  let name = value["name"]
			{
				newName = name
				dualHandler(200)
			} else {
				dualHandler(-1)
			}
		}
		let path = "/api/v2/userProfile/\(id)"
		guard let url = URL(string: PreferenceData.whisperServer + path) else {
			fatalError("Can't create URL for user profile download")
		}
		var request = URLRequest(url: url)
		request.setValue("Bearer \(serverPassword)", forHTTPHeaderField: "Authorization")
		request.httpMethod = "GET"
		Data.executeJSONRequest(request, handler: nameHandler)
	}
}
