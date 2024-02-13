// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation

extension Data {
	func saveJsonToDocumentsDirectory(_ filename: String) -> Bool {
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

	static func loadJsonFromDocumentsDirectory(_ filename: String, deleteAfter: Bool = false) -> Data? {
		do {
			let folderURL = try FileManager.default.url(
				for: .documentDirectory,
				in: .userDomainMask,
				appropriateFor: nil,
				create: false
			)
			let fileUrl = folderURL.appendingPathComponent("\(filename).json")
			let data = try Data(contentsOf: fileUrl)
			if deleteAfter {
				try? FileManager.default.removeItem(at: fileUrl)
			}
			return data
		}
		catch (let err) {
			logger.error("Failure reading \(filename).json: \(err)")
			return nil
		}
	}
}
