// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation

/// core hasher structure taken from Stack Overflow:
/// https://stackoverflow.com/a/62571311/558006
struct HasherFNV1a {

	private var hash: UInt = 14_695_981_039_346_656_037
	private let prime: UInt = 1_099_511_628_211

	mutating func combine<S: Sequence>(_ sequence: S) where S.Element == UInt8 {
		for byte in sequence {
			hash ^= UInt(byte)
			hash = hash &* prime
		}
	}

	func finalize() -> Int {
		Int(truncatingIfNeeded: hash)
	}
}

/// extensions that allow for different types of input
extension HasherFNV1a {
	mutating func combine(_ string: String) {
		combine(string.utf8)
	}

	mutating func combine(_ bool: Bool) {
		combine(CollectionOfOne(bool ? 1 : 0))
	}

	/// conversion to bytes taken from Stack Overflow:
	/// https://stackoverflow.com/a/56964191/558006
	mutating func combine<T>(_ int: T) where T: FixedWidthInteger {
		combine(withUnsafeBytes(of: int.bigEndian, Array.init))
	}
}

/// static one-shot hasher
extension HasherFNV1a {
	static func hash(_ d: Data) -> Int {
		var hasher = Self()
		hasher.combine(d)
		return hasher.finalize()
	}
}
