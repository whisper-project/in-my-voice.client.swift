// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import CryptoKit

final class SettingsProfile: Codable {
	var id: String
	private var settings: String
	private var eTag: String
	private var serverPassword: String = ""

	private enum CodingKeys: String, CodingKey {
		case id, settings, eTag
	}

	private init(_ profileId: String) {
		id = profileId
		settings = PreferenceData.preferencesToJson()
		eTag = Insecure.MD5.hash(data: Data(settings.utf8)).map{ String(format: "%02x", $0) }.joined()
		save()
	}

	private func save(verb: String = "PUT", localOnly: Bool = false) {
		guard let data = try? JSONSerialization.data(withJSONObject: ["eTag": eTag]) else {
			fatalError("Cannot serialize eTag of settings profile")
		}
		guard data.saveJsonToDocumentsDirectory("SettingsProfile") else {
			fatalError("Cannot save settings profile to Documents directory")
		}
		if !localOnly && !serverPassword.isEmpty {
			saveToServer(verb: verb)
		}
	}

	static func load(_ profileId: String, serverPassword: String) -> SettingsProfile {
		if let data = Data.loadJsonFromDocumentsDirectory("SettingsProfile"),
		   let value = try? JSONSerialization.jsonObject(with: data) as? [String: String],
		   let tag = value["eTag"]
		{
			return reload(profileId, serverPassword: serverPassword, currentTag: tag)
		} else {
			return reload(profileId, serverPassword: serverPassword, currentTag: "")
		}
	}

	private static func reload(_ profileId: String, serverPassword: String, currentTag: String) -> SettingsProfile {
		let profile = SettingsProfile(profileId)
		if !serverPassword.isEmpty {
			profile.serverPassword = serverPassword
			if currentTag.isEmpty {
				// shared profile wasn't saved so post to the server
				logger.info("Uploading shared settings for the first time")
				profile.saveToServer(verb: "POST")
			} else if profile.eTag != currentTag {
				// settings have changed so update the server
				logger.info("Settings have changed: uploading to shared profile")
				profile.saveToServer()
			}
		}
		return profile
	}

	// notice any local changes and save them to server, indicate whether we did
	private func updateLocally() -> Bool {
		let tag = eTag
		let profile = SettingsProfile.reload(id, serverPassword: serverPassword, currentTag: tag)
		settings = profile.settings
		eTag = profile.eTag
		return tag != eTag
	}

	private func saveToServer(verb: String = "PUT") {
		guard let data = try? JSONEncoder().encode(self) else {
			fatalError("Cannot encode settings profile: \(self)")
		}
		let path = "/api/v2/settingsProfile" + (verb == "PUT" ? "/\(id)" : "")
		guard let url = URL(string: PreferenceData.whisperServer + path) else {
			fatalError("Can't create URL for listen profile upload")
		}
		logger.info("\(verb) of settings profile to server, current Tag: \(self.eTag)")
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
		if updateLocally() {
			notifyChange?()
			return
		}
		func handler(_ code: Int, _ data: Data) {
			if code == 200 {
				if let profile = try? JSONDecoder().decode(SettingsProfile.self, from: data) {
					logger.info("Received updated settings profile, eTag is \(profile.eTag)")
					self.settings = profile.settings
					self.eTag = profile.eTag
					PreferenceData.jsonToPreferences(profile.settings)
					save(localOnly: true)
					notifyChange?()
				} else {
					logAnomaly("Received invalid settings profile data: \(String(decoding: data, as: UTF8.self))")
				}
			} else if code == 404 {
				logger.info("Posting missing settings profile, eTag is \(self.eTag)")
				save(verb: "POST")
			}
		}
		let path = "/api/v2/settingsProfile/\(id)"
		guard let url = URL(string: PreferenceData.whisperServer + path) else {
			fatalError("Can't create URL for settings profile download")
		}
		var request = URLRequest(url: url)
		request.setValue("Bearer \(serverPassword)", forHTTPHeaderField: "Authorization")
		request.setValue("\"\(self.eTag)\"", forHTTPHeaderField: "If-None-Match")
		request.setValue(PreferenceData.clientId, forHTTPHeaderField: "X-Client-Id")
		request.httpMethod = "GET"
		Data.executeJSONRequest(request, handler: handler)
	}

	func startSharing(serverPassword: String) {
		// get any changes
		let profile = SettingsProfile(self.id)
		self.settings = profile.settings
		self.eTag = profile.eTag
		self.serverPassword = serverPassword
		save(verb: "POST")
	}

	func loadShared(id: String, serverPassword: String, completionHandler: @escaping (Int) -> Void) {
		func handler(_ code: Int, _ data: Data) {
			if code == 404 {
				// if the server doesn't have settings in the profile,
				// we upload the current settings for use with the profile.
				let profile = SettingsProfile(id)
				self.id = id
				self.settings = profile.settings
				self.eTag = profile.eTag
				self.serverPassword = serverPassword
				save(verb: "POST")
				completionHandler(200)
			} else if code < 200 || code > 300 {
				completionHandler(code)
			} else if let profile = try? JSONDecoder().decode(SettingsProfile.self, from: data)
			{
				self.id = id
				self.serverPassword = serverPassword
				self.settings = profile.settings
				self.eTag = profile.eTag
				PreferenceData.jsonToPreferences(profile.settings)
				save(localOnly: true)
				completionHandler(200)
			} else {
				logAnomaly("Received invalid settings profile data: \(String(decoding: data, as: UTF8.self))")
				completionHandler(-1)
			}
		}
		let path = "/api/v2/settingsProfile/\(id)"
		guard let url = URL(string: PreferenceData.whisperServer + path) else {
			fatalError("Can't create URL for settings profile download")
		}
		var request = URLRequest(url: url)
		request.setValue("Bearer \(serverPassword)", forHTTPHeaderField: "Authorization")
		request.setValue(PreferenceData.clientId, forHTTPHeaderField: "X-Client-Id")
		request.setValue("\"  impossible-etag   \"", forHTTPHeaderField: "If-None-Match")
		request.httpMethod = "GET"
		Data.executeJSONRequest(request, handler: handler)
	}
}
