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
		lineWorkQueue.sync {
			sendPendingStats()
		}
	}

	static func notifyForeground() {
		sendRequest(path: "/foreground", method: "POST", query: nil, body: nil)
	}

	static func notifyBackground() {
		sendRequest(path: "/background", method: "POST", query: nil, body: nil)
	}

	static func notifyQuit() {
		sendRequest(path: "/shutdown", method: "POST", query: nil, body: nil)
		lineWorkQueue.sync {
			saveLineStats()
		}
	}

	static func notifyCompleteLine(changes: Int, startTime: Date?, durationMs: Int?, text: String) {
		guard PreferenceData.inStudy != nil else { return }
		var duration: Int = 0
		if let startTime = startTime {
			duration = Int((Date.now.timeIntervalSince(startTime)) * 1000)
		}
		if let durationMs = durationMs {
			duration += durationMs
		}
		if changes > 0 || duration > 0 {
			lineWorkQueue.sync {
				sendLineData(["completed": Int(Date.now.timeIntervalSince1970 * 1000),
							  "changes": changes, "duration": duration, "length": text.count])
			}
		}
	}

	static func notifyRepeatLine(isFavorite: Bool, text: String) {
		guard PreferenceData.inStudy != nil else { return }
		lineWorkQueue.sync {
			sendLineData(["isFavorite": isFavorite, "text": text],
						 ["completed": Int(Date.now.timeIntervalSince1970 * 1000),
						  "changes": 0, "duration": 0, "length": text.count])
		}
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

	static func fetchStudies(_ completionHandler: @escaping ([String: String], Bool) -> Void) {
		sendRequest(path: "/fetch-studies", method: "GET", query: nil, body: nil) { status, data in
			if status == 200,
			   let studies = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String]
			{
				completionHandler(studies, true)
				return
			}
			completionHandler([:], false)
		}
	}

	static func notifyJoinStudy(_ studyId: String, _ upn: String, _ completionHandler: @escaping (Int) -> Void) {
		sendRequest(path: "/join-study", method: "POST", query: nil,
					body: toData(["studyId": studyId, "upn": upn])) { status, _ in
			completionHandler(status)
		}
	}

	static func notifyLeaveStudy(_ completionHandler: @escaping (Bool) -> Void) {
		sendRequest(path: "/leave-study", method: "POST", query: nil, body: nil) { status, _ in
			completionHandler(status == 204)
		}
	}

	static func compareStudyElevenLabsSettings(updateIfDifferent: Bool, _ callback: @escaping (Bool) -> Void) {
		let completionHandler: (Int, Data) -> Void = { status, _ in
			callback(status == 200)
		}
		sendRequest(path: "/participant-settings/eleven", method: "GET",
					query: ["update": "\(updateIfDifferent)"], body: nil, handler: completionHandler)
	}

	static func downloadElevenLabsSettings(_ dataHandler: @escaping (Data?) -> Void) {
		let completionHandler: (Int, Data) -> Void = { status, data in
			switch status {
			case 200:
				dataHandler(data)
			case 204:
				// no settings available, let handler know
				dataHandler(Data())
			default:
				notifyAnomaly("Failed to download Eleven Labs settings: status code \(status)")
				// error on the server side, let handler know
				dataHandler(nil)
			}
		}
		sendRequest(path: "/speech-settings/eleven", method: "GET", query: nil, body: nil, handler: completionHandler)
	}

	static func proposeElevenLabsSettings(_ settings: Data, _ completionHandler: @escaping (Int, Data?) -> Void) {
		sendRequest(path: "/speech-settings/eleven", method: "POST", query: nil, body: settings, handler: completionHandler)
	}

	static func downloadFavorites(_ dataHandler: @escaping (Data) -> Void) {
		let completionHandler: (Int, Data) -> Void = { status, data in
			switch status {
			case 200:
				dataHandler(data)
			case 204:
				// no favorites available, let handler know
				dataHandler(Data())
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
		let requestDescription = "\(method) \(uri)"
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
		request.setValue("swift-v1|\(platformInfo)|\(versionString)", forHTTPHeaderField: "X-Client-Type")
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
			logger.info("\(requestDescription, privacy: .public): response \(code) with \(body.count) byte body")
			processResponseHeaders(response)
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
		logger.info("Executing \(requestDescription, privacy: .public)")
		task.resume()
	}

	private static func processResponseHeaders(_ response: HTTPURLResponse) {
		if let inStudy = response.value(forHTTPHeaderField: "X-Study-Membership-Update") {
			logger.info("Received notification of study membership: \(inStudy, privacy: .public)")
			PreferenceData.inStudy = inStudy
		}
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
		if response.value(forHTTPHeaderField: "X-Usage-Update") != nil {
			logger.info("Received notification of updated usage")
			ElevenLabs.shared.notifyUsage()
		}
	}

	private static var lineWorkQueue = DispatchQueue(label: "lineQueue", qos: .utility)
	private static var lineStatsPendingQueue: [[String:Any]] = []
	private static var lineStatsSubmissionId: Int64 = 0
	private static var lineStatsSubmissionsQueue: [Int64] = []
	private static var lineStatsSubmissionCounts: [Int64:Int64] = [:]

	// always perform this on the lineWorkQueue
	private static func sendPendingStats() {
		if let data = Data.loadJsonFromDocumentsDirectory("line-data") {
			Data.removeJsonFromDocumentsDirectory("line-data")
			if let stats = try? JSONSerialization.jsonObject(with: data) as? [[String:Any]] {
				lineStatsPendingQueue = stats
				sendLineData()
			} else {
				notifyAnomaly("Could not deserialize pending stats data.")
			}
		}
	}

	// always perform this on the lineWorkQueue
	private static func saveLineStats() {
		guard lineStatsPendingQueue.count > 0 else {
			Data.removeJsonFromDocumentsDirectory("line-data")
			return
		}
		if let data = try? JSONSerialization.data(withJSONObject: lineStatsPendingQueue, options: .prettyPrinted) {
			data.saveJsonToDocumentsDirectory("line-data")
		} else {
			notifyAnomaly("Failed to serialize pending stats data.")
		}
	}

	// always perform this on the lineWorkQueue
	private static func sendLineData(_ data: [String:Any]...) {
		let requestData = lineStatsPendingQueue + data
		lineStatsPendingQueue = []
		guard let body = try? JSONSerialization.data(withJSONObject: requestData) else {
			notifyAnomaly("Failed to serialize stats data for request, discarding it.")
			return
		}
		let uri = "\(PreferenceData.appServer)/api/swift/v1/line-data"
		var request = URLRequest(url: URL(string: uri)!)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = body
		request.setValue(PreferenceData.clientId, forHTTPHeaderField: "X-Client-Id")
		request.setValue(PreferenceData.profileId!, forHTTPHeaderField: "X-Profile-Id")
		request.setValue(platformInfo, forHTTPHeaderField: "X-Platform-Info")
		let task = URLSession.shared.dataTask(with: request) { (_, response, error) in
			lineWorkQueue.sync { processOneResponse(error == nil, requestData) }
			if let response = response as? HTTPURLResponse {
				processResponseHeaders(response)
			}
		}
		logger.info("Sending line stats, count: \(requestData.count)")
		task.resume()
	}

	// always perform this on the lineWorkQueue
	private static func processOneResponse(_ success: Bool, _ data: [[String:Any]]) {
		if !success {
			logger.info("Requeueing line stats, count: \(data.count)")
			lineStatsPendingQueue.append(contentsOf: data)
		}
	}
}
