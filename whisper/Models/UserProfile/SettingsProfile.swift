// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import CryptoKit

final class SettingsProfile: Codable {
	static private let saveName = PreferenceData.profileRoot + "SettingsProfile"
	
	var id: String
	private var settings: String
	private var eTag: String
	private var version: Int
	private var serverPassword: String = ""

	private enum CodingKeys: String, CodingKey {
		case id, settings, version, eTag
	}

	private init(_ profileId: String) {
		id = profileId
		version = PreferenceData.preferenceVersion
		settings = PreferenceData.preferencesToJson()
		eTag = Insecure.MD5.hash(data: Data(settings.utf8)).map{ String(format: "%02x", $0) }.joined()
		save(localOnly: true)
	}

	private func save(verb: String = "PUT", localOnly: Bool = false) {
		guard let data = try? JSONSerialization.data(withJSONObject: ["version": "\(version)", "eTag": eTag]) else {
			fatalError("Cannot serialize version and eTag of settings profile")
		}
		guard data.saveJsonToDocumentsDirectory(SettingsProfile.saveName) else {
			fatalError("Cannot save settings profile to Documents directory")
		}
		if !localOnly && !serverPassword.isEmpty {
			saveToServer(verb: verb)
		}
	}

	static func load(_ profileId: String, serverPassword: String) -> SettingsProfile {
		if let data = Data.loadJsonFromDocumentsDirectory(SettingsProfile.saveName),
		   let value = try? JSONSerialization.jsonObject(with: data) as? [String: String],
		   let name = value["eTag"]
		{
			let version = Int(value["version"] ?? "none")
			return reloadLocal(profileId, serverPassword: serverPassword, lastVersion: version, lastTag: name).0
		} else {
			return reloadLocal(profileId, serverPassword: serverPassword, lastVersion: nil, lastTag: nil).0
		}
	}

	private static func reloadLocal(_ profileId: String,
									serverPassword: String,
									lastVersion: Int?,
									lastTag: String?) -> (profile: SettingsProfile, didUpload: Bool) {
		// load the current settings and save them locally
		let profile = SettingsProfile(profileId)
		// figure out if we should save them to the server
		if serverPassword.isEmpty {
			return (profile, false)
		} else {
			profile.serverPassword = serverPassword
		}
		guard lastVersion == PreferenceData.preferenceVersion else {
			logAnomaly("Saved shared settings profile is out of date (\(lastVersion ?? 0)), not saving it to server")
			return (profile, false)
		}
		if lastTag == profile.eTag {
			// there have been no local changes
			return (profile, false)
		}
		if lastTag == nil {
			// This profile has never been saved and yet it's shared
			// This can only happen when there's no saved local settings profile,
			// so it's a bit anomalous because we've had local settings profiles for a while now.
			logAnomaly("Shared settings were never saved locally, so trying to upload them now")
			profile.saveToServer(verb: "POST")
		} else {
			// our local version is current and differs from what we last saved
			logger.info("Settings have changed: uploading to shared profile")
			profile.saveToServer()
		}
		return (profile, true)
	}

	// notice any local changes and save them to server, indicate whether we did
	private func updateLocally() -> Bool {
		let result = SettingsProfile.reloadLocal(id, serverPassword: serverPassword, lastVersion: version, lastTag: eTag)
		version = result.profile.version
		settings = result.profile.settings
		eTag = result.profile.eTag
		return result.didUpload
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
				if maybeInstallReceivedProfile(data) > 0 {
					notifyChange?()
				}
			} else if code == 404 {
				logAnomaly("Posting missing shared settings profile (v\(self.version)), eTag is \(self.eTag)")
				saveToServer(verb: "POST")
			} else if code == 409 {
				logger.debug("Server settings profile matches local settings profile, so no update done.")
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
		// get any local changes, then post
		let profile = SettingsProfile(id)
		self.serverPassword = serverPassword
		self.version = profile.version
		self.eTag = profile.eTag
		self.settings = profile.settings
		saveToServer(verb: "POST")
	}

	func loadShared(id: String, serverPassword: String, completionHandler: @escaping (Int) -> Void) {
		func handler(_ code: Int, _ data: Data) {
			if code == 404 {
				logAnomaly("No shared settings profile found on server, uploading ours")
				startSharing(serverPassword: self.serverPassword)
				completionHandler(200)
			} else if code < 200 || code >= 300 {
				completionHandler(code)
			} else {
				// we have received a profile, so we know the id and password are good
				self.id = id
				self.serverPassword = serverPassword
				if maybeInstallReceivedProfile(data) >= 0 {
					completionHandler(200)
				} else {
					completionHandler(-1)
				}
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

	// tries to decode and install received settings profile
	// returns 1 if profile was decoded and installed
	// returns 0 if profile was decoded but couldn't be installed
	// returns -1 if profile could not be decoded
	private func maybeInstallReceivedProfile(_ data: Data) -> Int {
		if let profile = try? JSONDecoder().decode(SettingsProfile.self, from: data) {
			logger.info("Received shared settings profile (v\(profile.version)), eTag is \(profile.eTag)")
			let expected = PreferenceData.preferenceVersion
			guard profile.version == expected else {
				logAnomaly("Expected v\(expected) but received v\(profile.version) settings profile, uploading new")
				saveToServer()
				return 0
			}
			self.version = profile.version
			self.eTag = profile.eTag
			self.settings = profile.settings
			PreferenceData.jsonToPreferences(profile.settings)
			save(localOnly: true)
			return 1
		} else {
			logAnomaly("Received invalid shared settings profile data: \(String(decoding: data, as: UTF8.self))")
			return -1
		}
	}
}
