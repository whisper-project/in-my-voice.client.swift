// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation

/// The point of this protocol is to incrementally send user-entered live text from
/// the whisperer to the listeners.  Since it's a BLE protocol,  we want the packet
/// sizes to be small.  Because the data is both read directly by the Central
/// (when a new listener joins) and subscribed to by the Central, we need to
/// make sure that replaying a suffix sequence of packets is idempotent.
///
/// The design is to send a packet each time the user changes the live text,
/// and to include in each packet the offset in the existing text at which
/// the change starts.  If a listener receives an offset that's shorter than
/// his current text, he can assume the user has revised earlier text.
/// If a listener receives an offset that's longer than his current text, he
/// can assume he's missed a packet and call for a new read of the data,
/// suspending incremental packet processing until the full data is received.
///
/// Each data packet is a utf8-encoded string in three parts:
///
/// - a decimal integer offset
/// - a vertical bar '|' dividing the offset from the text
/// - the text of the line that starts at the offset
///
/// Broadcast packets (sent to all listeners) are "diffs" of the current type and
/// always have an offset >= -1:
/// - Offsets >= 0 indicate that the text replaces text in the currently-being-typed
/// line starting at that offset.
/// - An offset of -1 indicates an incremental newline:
/// the was-being-typed line was completed and new typing is starting.
///
/// Direct read packets (sent only to listeners that
/// request a full read of the data) have offsets of -2 or -3 or -4:
/// - An offset of -2 indicates that the packet contains an entire line of typing:
/// the text is a past- completed line.
/// - An offset of -3 indicates that the packet contains the currently-being-typed
/// line and is always the last packet received from a direct read.
/// - An offset of -4 is a chunk that is sent to acknowledge a read request,
/// and indicates that a requested replay to the requesting listener is being sent. The
/// text portion of the chunk is the hint that was received in the read request.
///
/// Sound packets (sent to all listeners) have an offset of -9, and the text
/// indicates the command being sent.
///
/// Control packets communicate requests rather than :
/// - Offset -20 requests the whisperer to replay past text.  The text
/// portion is used by the receiver as a hint of how much past text to send,
/// and is typically "all" (the default), "lines N" meaning the most recent N lines,
/// or "since N" meaning lines send within the last N seconds.
/// - Offset -21 is the whisperer telling the listener to stop listening.  The
/// text is the id of the listener it's meant for.  It's how dropping a listener works
/// over the network.
final class TextProtocol {
    struct ProtocolChunk {
        var offset: Int
        var text: String
        
        func toString() -> String {
            return "\(offset)|" + text
        }
        
        func toData() -> Data {
            return Data(self.toString().utf8)
        }
        
        static func fromString(_ string: String) -> ProtocolChunk? {
            let parts = string.split(separator: "|", maxSplits: 1)
            if parts.count == 0 {
                // data packets with no "|" character are malformed
                return nil
            } else if let offset = Int(parts[0]) {
                return ProtocolChunk(offset: offset, text: parts.count == 2 ? String(parts[1]) : "")
            } else {
                // data packets with no int before the "|" are malformed
                return nil
            }
        }
        
        static func fromData(_ data: Data) -> ProtocolChunk? {
            return fromString(String(decoding: data, as: UTF8.self))
        }

        func isDiff() -> Bool {
            offset >= -1
        }
        
        func isCompleteLine() -> Bool {
            return offset == -1 || offset == -2
        }
        
        func isLastRead() -> Bool {
            return offset == -3
        }
        
        func isFirstRead() -> Bool {
            return offset == -4
        }
        
        func isSound() -> Bool {
            return offset == -9
        }
        
        func isReplayRequest() -> Bool {
            return offset == -20
        }
        
        func isDropRequest() -> Bool {
            return offset == -21
        }
        
        static func fromPastText(text: String) -> ProtocolChunk {
            return ProtocolChunk(offset: -2, text: text)
        }
        
        static func fromLiveText(text: String) -> ProtocolChunk {
            return ProtocolChunk(offset: -3, text: text)
        }
        
        static func acknowledgeRead(hint: String) -> ProtocolChunk {
            return ProtocolChunk(offset: -4, text: hint)
        }
        
        static func sound(_ text: String) -> ProtocolChunk {
            return ProtocolChunk(offset: -9, text: text)
        }
        
        static func replayRequest(hint: String) -> ProtocolChunk {
            return ProtocolChunk(offset: -20, text: hint)
        }
        
        static func dropRequest(id: String) -> ProtocolChunk {
            return ProtocolChunk(offset: -21, text: id)
        }
        
        static func fromLiveTyping(text: String, start: Int) -> [ProtocolChunk] {
            guard text.count > start else {
                return []
            }
            let lines = text.suffix(text.count - start).split(separator: "\n", omittingEmptySubsequences: false)
            var result: [ProtocolChunk] = [ProtocolChunk(offset: start, text: String(lines[0]))]
            for line in lines.dropFirst() {
                result.append(ProtocolChunk(offset: -1, text: ""))
                result.append(ProtocolChunk(offset: 0, text: String(line)))
            }
            return result
        }
    }
    
    /// Create a series of incremental protocol chunks that will turn the old typing into the new typing.
    /// The old typing is assumed not to have any newlines in it.  The new typing may have
    /// newlines in it, in which case there will be multiple chunks in the output with an
    /// incremental complete line chunk for every newline.
    static func diffLines(old: String, new: String) -> [ProtocolChunk] {
        let matching = zip(old.indices, new.indices)
        for (i, j) in matching {
            if old[i] != new[j] {
                return ProtocolChunk.fromLiveTyping(text: new, start: old.distance(from: old.startIndex, to: i))
            }
        }
        // if we fall through, one is a substring of the other
        if old.count == new.count {
            // no changes
            return []
        } else if old.count < new.count {
            return ProtocolChunk.fromLiveTyping(text: new, start: old.count)
        } else {
            // new is a prefix of old
            return [ProtocolChunk(offset: new.count, text: "")]
        }
    }
    
    /// Apply a single, incremental text chunk to the old typing (which has no newlines).
    static func applyDiff(old: String, chunk: ProtocolChunk) -> String {
        let prefix = String(old.prefix(chunk.offset))
        return prefix + chunk.text
    }
}
