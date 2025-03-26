// Copyright 2025 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine

class ServerProtocol {
	static var messageSubject: CurrentValueSubject<String?, Never> = .init(nil)

	static func notifyAnomaly(_ message: String) {
		logger.warning("Anomaly reported: \(message, privacy: .public)")
		sendRequest(path: "/anomaly", method: "POST", query: nil, body: toData(["message": message]), handler: { _, _ in })
	}

	static func notifyLaunch() {
		sendRequest(path: "/launch", method: "POST", query: nil, body: nil)
	}

	static func notifyForeground() {
		sendRequest(path: "/foreground", method: "POST", query: nil, body: nil)
	}

	static func notifyBackground() {
		sendRequest(path: "/background", method: "POST", query: nil, body: nil)
	}

	static func notifyQuit() {
		sendRequest(path: "/shutdown", method: "POST", query: nil, body: nil)
	}

	static func notifyChangeData(count: Int, startTime: Date?, durationMs: Int?) {
		var duration: Int = 0
		if let startTime = startTime {
			duration = Int((Date.now.timeIntervalSince(startTime)) * 1000)
		}
		if let durationMs = durationMs {
			duration += durationMs
		}
		if count > 0 && duration > 0 {
			sendRequest(path: "/change-data", method: "POST", query: nil, body: toData(["count": count, "duration": duration]))
		}
	}

	static func notifyRepeatLine() {
		sendRequest(path: "/repeat-line", method: "POST", query: nil, body: nil)
	}

	static func notifyFavorite(_ text: String) {
		sendRequest(path: "/favorite", method: "POST", query: nil, body: toData(["text": text]))
	}

	static func notifyElevenLabsFailure(action: String, code: Int, data: Data?) {
		if let data = data {
			let body = String(decoding: data, as: UTF8.self)
			sendRequest(path: "/speech-failure/eleven", method: "POST", query: nil,
						body: toData(["action": action, "code": code, "response": body]))
		} else {
			sendRequest(path: "/speech-failure/eleven", method: "POST", query: nil,
						body: toData(["action": action, "code": code]))
		}
	}

	static func downloadElevenLabsSettings(_ dataHandler: @escaping (Data) -> Void) {
		let completionHandler: (Int, Data) -> Void = { status, data in
			switch status {
			case 200:
				dataHandler(data)
			case 204:
				// no settings available, don't call handler
				break
			default:
				notifyAnomaly("Failed to download Eleven Labs settings: status code \(status)")
			}
		}
		sendRequest(path: "/speech-settings/eleven", method: "GET", query: nil, body: nil, handler: completionHandler)
	}

	static func uploadElevenLabsSettings(_ settings: Data) {
		sendRequest(path: "/speech-settings/eleven", method: "PUT", query: nil, body: settings)
	}

	static func downloadFavorites(_ dataHandler: @escaping (Data) -> Void) {
		let completionHandler: (Int, Data) -> Void = { status, data in
			switch status {
			case 200:
				dataHandler(data)
			case 204:
				// no favorites available, don't call handler
				break
			default:
				notifyAnomaly("Failed to download favorites: status code \(status)")
			}
		}
		sendRequest(path: "/favorites", method: "GET", query: nil, body: nil, handler: completionHandler)
	}

	static func uploadFavorites(_ favorites: Data) {
		sendRequest(path: "/favorites", method: "PUT", query: nil, body: favorites)
	}

	private static func toData(_ body: [String: Any]) -> Data? {
		return try? JSONSerialization.data(withJSONObject: body, options: [])
	}

	private static func sendRequest(
		path: String, method: String, query: [String: String]?, body: Data?, handler: ((Int, Data) -> Void)? = nil
	) {
		var uri = "\(PreferenceData.appServer)/api/swift/v1\(path)"
		var logMessage = "\(method) \(uri)"
		if let query = query {
			uri += "?" + query.map { key, value in
				"\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
			}.joined(separator: "&")
		}
		var request = URLRequest(url: URL(string: uri)!)
		request.httpMethod = method
		if let body = body {
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.httpBody = body
		}
		request.setValue(PreferenceData.clientId, forHTTPHeaderField: "X-Client-Id")
		request.setValue(PreferenceData.profileId!, forHTTPHeaderField: "X-Profile-Id")
		request.setValue("swift-v0|\(platformInfo)|\(versionString)", forHTTPHeaderField: "X-Client-Type")
		let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
			guard error == nil else {
				logger.error("Failed to execute \(request, privacy: .public): \(String(describing: error), privacy: .public)")
				return
			}
			guard let response = response as? HTTPURLResponse else {
				logger.error("Received non-HTTP response to \(request, privacy: .public): \(String(describing: response), privacy: .public)")
				return
			}
			let code = response.statusCode
			let body = data ?? Data()
			logger.info("\(logMessage, privacy: .public): response \(code) with \(body.count) byte body")
			if let message = response.value(forHTTPHeaderField: "X-Message") {
				logger.info("Received server message: \(message, privacy: .public)")
				Self.messageSubject.send(message)
			}
			if let websiteLocation = response.value(forHTTPHeaderField: "X-Website-Location") {
				logger.info("Received updated website location: \(websiteLocation, privacy: .public)")
				PreferenceData.website = websiteLocation
			}
			if response.value(forHTTPHeaderField: "X-Speech-Settings-Update") != nil {
				logger.info("Received notification of updated speech settings")
				ElevenLabs.shared.downloadSettings()
			}
			if response.value(forHTTPHeaderField: "X-Favorites-Update") != nil {
				logger.info("Received notification of updated favorites")
				FavoritesProfile.shared.downloadFavorites()
			}
			switch code {
			case 404...405:
				fatalError("Received \(response.statusCode) response to \(method) on URI: \(uri)")
			case 500...502:
				logger.error("Server returned error \(code): \(String(decoding: body, as: Unicode.UTF8.self), privacy: .public)")
				Self.messageSubject.send("**There was a temporary problem on the server.**\nThe app is still working fine.\nThe server maintainers have been notified.")
			default:
				break
			}
			handler?(code, body)
		}
		logger.info("Executing \(logMessage, privacy: .public)")
		task.resume()
	}
}
