// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation

extension Data {
	@discardableResult func saveJsonToDocumentsDirectory(_ filename: String) -> Bool {
		do {
			let folderURL = try FileManager.default.url(
				for: .documentDirectory,
				in: .userDomainMask,
				appropriateFor: nil,
				create: false
			)
			let fileUrl = folderURL.appendingPathComponent("\(filename).json")
			try self.write(to: fileUrl)
			return true
		}
		catch (let err) {
			logger.error("Failed to write \(filename).json: \(err)")
			return false
		}
	}

	static func loadJsonFromDocumentsDirectory(_ filename: String) -> Data? {
		do {
			let folderURL = try FileManager.default.url(
				for: .documentDirectory,
				in: .userDomainMask,
				appropriateFor: nil,
				create: false
			)
			let fileUrl = folderURL.appendingPathComponent("\(filename).json")
			let data = try Data(contentsOf: fileUrl)
			return data
		}
		catch (let err) {
			logger.error("Failure reading \(filename).json: \(err)")
			return nil
		}
	}

	@discardableResult static func removeJsonFromDocumentsDirectory(_ filename: String) -> Bool {
		do {
			let folderURL = try FileManager.default.url(
				for: .documentDirectory,
				in: .userDomainMask,
				appropriateFor: nil,
				create: false
			)
			let fileUrl = folderURL.appendingPathComponent("\(filename).json")
			try FileManager.default.removeItem(at: fileUrl)
			return true
		}
		catch (let err) {
			logger.error("Failure deleting \(filename).json: \(err)")
			return false
		}
	}

	static func executeJSONRequest(_ request: URLRequest, handler: ((Int, Data) -> Void)? = nil) {
		let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
			guard error == nil else {
				logger.error("Failed to execute \(request): \(String(describing: error))")
				return
			}
			guard let response = response as? HTTPURLResponse else {
				logger.error("Received non-HTTP response to \(request): \(String(describing: response))")
				return
			}
			if (response.statusCode >= 200 && response.statusCode < 300) {
				if let data = data, data.count > 0 {
					logger.info("Received \(response.statusCode) response with \(data.count) byte body")
					handler?(response.statusCode, data)
				} else {
					logger.info("Received \(response.statusCode) response with empty body")
					handler?(response.statusCode, Data())
				}
			} else {
				if let data = data, data.count > 0 {
					if let message = String(data: data, encoding: .utf8) {
						logger.error("Received \(response.statusCode) response with message: \(message)")
					} else {
						logger.error("Received \(response.statusCode) reponse with non-UTF8 body: \(String(describing: data))")
					}
					handler?(response.statusCode, data)
				} else {
					logger.error("Received \(response.statusCode) response with no body")
					handler?(response.statusCode, Data())
				}
			}
		}
		logger.info("Executing \(request)")
		task.resume()
	}
}
