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
			ServerProtocol.notifyAnomaly("Failed to write \(filename).json: \(err)")
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
			if FileManager.default.fileExists(atPath: fileUrl.path) {
				let data = try Data(contentsOf: fileUrl)
				return data
			} else {
				return nil
			}
		}
		catch (let err) {
			ServerProtocol.notifyAnomaly("Failure reading \(filename).json: \(err)")
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
			if FileManager.default.fileExists(atPath: fileUrl.path) {
				try FileManager.default.removeItem(at: fileUrl)
			}
			return true
		}
		catch (let err) {
			ServerProtocol.notifyAnomaly("Failure deleting \(filename).json: \(err)")
			return false
		}
	}
}
