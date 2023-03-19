// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation

/// The point of this protocol is to incrementally send user-entered live text from
/// the whisperer to the listeners.  Since it's a BLE protocol,  we want the packet
/// sizes to be small.  Because the data is both read directly by the Central
/// (when a new listener joins) and subscribed to by the Central, we need to
/// make sure that replaying a suffix sequence of packets is idempotent, and
/// that the listener can tell if they've missed a packet (so they can re-read).
///
/// The design is to send a packet each time the user types a few characters,
/// and to include in each packet the offset in the existing text at which those
/// characters were typed.  If a listener receives an offset that's shorter than
/// his current text, he can assume the user has revised earlier text.
/// If a listener receives an offset that's longer than his current text, he
/// can assume he's missed a packet and call for a new read of the data,
/// suspending packet processing until the full data is received.
final class TextProtocol {
    struct ProtocolChunk {
        var start: UInt64
        var text: String
        
        func toData() -> Data {
            let string: String = "\(start)|" + text
            return Data(string.utf8)
        }
        
        static func fromData(_ data: Data) -> ProtocolChunk? {
            let parts = String(decoding: data, as: UTF8.self).split(separator: "|", maxSplits: 1)
            if parts.count == 0 {
                // data packets with no "|" character are malformed
                return nil
            } else {
                let offset = UInt64(parts[0]) ?? 0
                return ProtocolChunk(start: offset, text: parts.count == 2 ? String(parts[1]) : "")
            }
        }
    }
    
    static func diffLines(old: String, new: String) -> ProtocolChunk? {
        let matching = zip(old.indices, new.indices)
        for (i, j) in matching  {
            if old[i] != new[j] {
                if i == old.startIndex {
                    return ProtocolChunk(start: 0, text: new)
                } else {
                    return ProtocolChunk(start: UInt64(old.distance(from: old.startIndex, to: i)),
                                         text: String(new.suffix(from: j)))
                }
            }
        }
        // if we fall through, one is a substring of the other
        if old.count == new.count {
            // no changes
            return nil
        } else if old.count < new.count {
            // old is a prefix of new
            return ProtocolChunk(start: UInt64(old.count), text: String(new.suffix(new.count - old.count)))
        } else {
            // new is a prefix of old
            return ProtocolChunk(start: UInt64(new.count), text: "")
        }
    }
    
    static func applyDiff(old: String, chunk: ProtocolChunk) -> String {
        let prefix = String(old.prefix(Int(chunk.start)))
        return prefix + chunk.text
    }
}
