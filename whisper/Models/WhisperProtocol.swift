// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation

/// The original point of this protocol was to incrementally send user-entered live text from
/// the whisperer to the listeners.  That's still a goal, but it has been enhanced to handle
/// invites, conversation IDs, and communication controls between whisperer and listener.
/// See the design docs for more detail.
final class WhisperProtocol {
    enum ControlOffset: Int, CustomStringConvertible {
        /// text control messages
        case newline = -1           // Shift current live text to past text (no packet data)
        case pastText = -2          // Add single line of past text given by packet data
        case liveText = -3          // Replace current live text with packet data
        case startReread = -4       // Start sending re-read.  Packet data is `ReadType` being sent.
        case requestReread = -5     // Request re-read. Packet data is `ReadType` of request.
        case clearHistory = -6      // Tell Listener to clear their history.
        
        /// sound control messages
        case playSound = -10        // Play the sound named by the packet data.
        case playSpeech = -11       // Generate speech for the packet data.
        
        /// handshake control messages - packet data for all these is the [ClientInfo]
        case whisperOffer = -20     // Whisperer offers a conversation to listener
        case listenRequest = -21    // Listener requests to join a conversation
        case listenAuthYes = -22    // Whisperer authorizes Listener to join a conversation.
        case listenAuthNo = -23     // Whisperer doesn't authorize Listener to join a conversation.
        case joining = -24          // An allowed listener is joining the conversation.
        case dropping = -25         // A whisperer or listener is dropping from the conversation.
        
        /// discovery control messages
        case listenOffer = -30      // A Listener is looking to rejoin a conversation: packet data is client ID and profile ID.

        var description: String {
            switch self {
            case .newline:
                return "newline"
            case .pastText:
                return "past text"
            case .liveText:
                return "live text"
            case .startReread:
                return "start reread"
            case .requestReread:
                return "request reread"
            case .clearHistory:
                return "clear history"
            case .playSound:
                return "play sound"
            case .playSpeech:
                return "play speech"
            case .whisperOffer:
                return "whisper offer"
            case .listenRequest:
                return "listen request"
            case .listenAuthYes:
                return "listen authorization"
            case .listenAuthNo:
                return "listen deauthorization"
            case .joining:
                return "joining"
            case .dropping:
                return "dropping"
            case .listenOffer:
                return "listen offer"
            }
        }
    }
    
    /// Reads allow the whisperer to update a listener which is out of sync.
    /// Each read sequence has a "type" indicating which text it's reading.
    enum ReadType: String {
        case live = "live"
        case past = "past"
        case all = "all"
    }
    
    /// Client info as passed in the packet data of invites
    struct ClientInfo {
        var conversationId: String
        var conversationName: String
        var clientId: String
        var profileId: String
        var username: String
        var contentId: String
        
        func toString() -> String {
            return "\(conversationId)|\(conversationName)\(clientId)|\(profileId)|\(username)"
        }
        
        static func fromString(_ s: String) -> ClientInfo? {
            let parts = s.split(separator: "|")
            if parts.count != 6 {
                logger.error("Malformed TextProtocol.ClientInfo data: \(s))")
                return nil
            }
            return ClientInfo(conversationId: String(parts[0]),
                              conversationName: String(parts[1]),
                              clientId: String(parts[2]),
                              profileId: String(parts[3]),
                              username: String(parts[4]),
                              contentId: String(parts[5]))
        }
    }
    
    struct ProtocolChunk {
        var offset: Int
        var text: String
        
        func toString() -> String {
            return "\(offset)|" + text
        }
        
        func toData() -> Data {
            return Data(self.toString().utf8)
        }
        
        static func fromString(_ s: String) -> ProtocolChunk? {
            let parts = s.split(separator: "|", maxSplits: 1)
            if parts.count == 0 {
                // data packets with no "|" character are malformed
                logger.error("Malformed TextProtocol.ProtocolChunk data: \(s))")
                return nil
            } else if let offset = Int(parts[0]) {
                return ProtocolChunk(offset: offset, text: parts.count == 2 ? String(parts[1]) : "")
            } else {
                // data packets with no int before the "|" are malformed
                logger.error("Malformed TextProtocol.ProtocolChunk data: \(s))")
                return nil
            }
        }
        
        static func fromData(_ data: Data) -> ProtocolChunk? {
            return fromString(String(decoding: data, as: UTF8.self))
        }
        
        /// a "diff" packet is one that incrementally affects live text
        func isDiff() -> Bool {
            offset >= ControlOffset.newline.rawValue
        }
        
        func isCompleteLine() -> Bool {
            return offset == ControlOffset.newline.rawValue || offset == ControlOffset.pastText.rawValue
        }
        
        func isLastRead() -> Bool {
            return offset == ControlOffset.liveText.rawValue
        }
        
        func isFirstRead() -> Bool {
            return offset == ControlOffset.startReread.rawValue
        }
        
        func isSound() -> Bool {
            return offset == ControlOffset.playSound.rawValue
        }
        
        func isReplayRequest() -> Bool {
            return offset == ControlOffset.requestReread.rawValue
        }
        
        func isPresenceMessage() -> Bool {
            return (offset <= ControlOffset.whisperOffer.rawValue &&
                    offset >= ControlOffset.listenOffer.rawValue)
        }
        
        func isListenOffer() -> Bool {
            return offset == ControlOffset.listenOffer.rawValue
        }
        
        static func fromPastText(text: String) -> ProtocolChunk {
            return ProtocolChunk(offset: ControlOffset.pastText.rawValue, text: text)
        }
        
        static func fromLiveText(text: String) -> ProtocolChunk {
            return ProtocolChunk(offset: ControlOffset.liveText.rawValue, text: text)
        }
        
        static func acknowledgeRead(hint: ReadType) -> ProtocolChunk {
            return ProtocolChunk(offset: ControlOffset.startReread.rawValue, text: hint.rawValue)
        }
        
        static func sound(_ text: String) -> ProtocolChunk {
            return ProtocolChunk(offset: ControlOffset.playSound.rawValue, text: text)
        }
        
        static func replayRequest(hint: ReadType) -> ProtocolChunk {
            return ProtocolChunk(offset: ControlOffset.requestReread.rawValue, text: hint.rawValue)
        }
        
        private static func presenceChunk(offset: Int, c: Conversation, contentId: String = "") -> ProtocolChunk {
            let profile = UserProfile.shared
            let data = ClientInfo(conversationId: c.id,
                                  conversationName: c.name,
                                  clientId: PreferenceData.clientId,
                                  profileId: profile.id,
                                  username: profile.username,
                                  contentId: contentId)
            return ProtocolChunk(offset: offset, text: data.toString())
        }
        
        static func whisperOffer(c: Conversation) -> ProtocolChunk {
            return presenceChunk(offset: ControlOffset.whisperOffer.rawValue, c: c)
        }
        
        static func listenRequest(c: Conversation) -> ProtocolChunk {
            return presenceChunk(offset: ControlOffset.listenRequest.rawValue, c: c)
        }
        
        static func listenAuthYes(c: Conversation, contentId: String) -> ProtocolChunk {
            return presenceChunk(offset: ControlOffset.listenAuthYes.rawValue, c: c)
        }
        
        static func listenAuthNo(c: Conversation) -> ProtocolChunk {
            return presenceChunk(offset: ControlOffset.listenAuthYes.rawValue, c: c)
        }
        
        static func joining(c: Conversation) -> ProtocolChunk {
            return presenceChunk(offset: ControlOffset.joining.rawValue, c: c)
        }
        
        static func dropping(c: Conversation) -> ProtocolChunk {
            return presenceChunk(offset: ControlOffset.dropping.rawValue, c: c)
        }
        
		static func listenOffer(_ c: Conversation? = nil) -> ProtocolChunk {
			let info = ClientInfo(conversationId: c?.id ?? "",
                                  conversationName: "",
                                  clientId: PreferenceData.clientId,
                                  profileId: UserProfile.shared.id,
                                  username: "",
                                  contentId: "")
            return ProtocolChunk(offset: ControlOffset.listenOffer.rawValue, text: info.toString())
        }
        
        static func fromLiveTyping(text: String, start: Int) -> [ProtocolChunk] {
            guard text.count > start else {
                return []
            }
            let lines = text.suffix(text.count - start).split(separator: "\n", omittingEmptySubsequences: false)
            var result: [ProtocolChunk] = [ProtocolChunk(offset: start, text: String(lines[0]))]
            for line in lines.dropFirst() {
                result.append(ProtocolChunk(offset: ControlOffset.newline.rawValue, text: ""))
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
