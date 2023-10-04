// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation

struct PastTextLine: Identifiable {
    var text: String
    var id: Int     // line number
}

final class PastTextViewModel: ObservableObject {
    @Published var pastText: String
    @Published private(set) var addLinesAtTop = false
    
    init(mode: OperatingMode, initialText: String = "") {
        if mode == .listen && !PreferenceData.listenerMatchesWhisperer() {
            addLinesAtTop = true
        }
        self.pastText = initialText
    }
    
    func addLine(_ line: String) {
        if addLinesAtTop {
            pastText = line + "\n" + pastText
        } else {
            pastText += "\n" + line
        }
    }
    
    func clearLines() {
        pastText = ""
    }
    
    func getLines() -> [String] {
        var lines = pastText.split(separator: "\n", omittingEmptySubsequences: false)
        if addLinesAtTop {
            lines.reverse()
        }
        return lines.map{ String($0) }
    }
    
    func addText(_ text: String) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            addLine(String(line))
        }
    }
    
    func setFromText(_ text: String) {
        clearLines()
        addText(text)
    }
}
