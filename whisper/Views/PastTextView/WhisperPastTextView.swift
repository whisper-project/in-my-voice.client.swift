// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct WhisperPastTextView: View {
	@ObservedObject var model: PastTextModel
	var repeatLine: ((String) -> Void)?

    var body: some View {
		ScrollViewReader { proxy in
			List {
				ForEach(makeRows(model.pastText)) { row in
					HStack(spacing: 20) {
						Button("Repeat", systemImage: "repeat") {
							repeatLine?(row.text)
						}
						.labelStyle(.iconOnly)
						.buttonStyle(.bordered)
						.font(.title)
						Text(row.text)
							.lineLimit(nil)
					}
					.id(row.id)
				}
			}
		}
    }

	private struct Row: Identifiable {
		let id: Int
		let text: String
	}

	private func makeRows(_ text: String) -> [Row] {
		var rows: [Row] = []
		let lines = text.split(separator: "\n")
		let max = lines.count - 1
		for (i, line) in lines.enumerated() {
			rows.append(Row(id: i - max, text: String(line)))
		}
		return rows
	}
}

#Preview {
	WhisperPastTextView(model: PastTextModel(mode: .whisper, initialText: """
		line 1
		line 2
		line 3
		line 4
	"""))
}
