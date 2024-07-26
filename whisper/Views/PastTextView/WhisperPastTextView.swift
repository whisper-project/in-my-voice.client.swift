// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct WhisperPastTextView: View {
	@Binding var interjecting: Bool
	@ObservedObject var model: PastTextModel
	var again: ((String?) -> Void)?
	var edit: ((String) -> Void)?

	@AppStorage("history_buttons_preference") private var buttonsPref: String?

    var body: some View {
		ScrollViewReader { proxy in
			List {
				ForEach(makeRows(model.pastText)) { row in
					HStack(spacing: 5) {
						makeButtons(row)
						Text(row.text)
							.lineLimit(nil)
					}
					.id(row.id)
				}
			}
			.listStyle(.plain)
			.onChange(of: model.pastText) {
				if !model.pastText.isEmpty {
					proxy.scrollTo(0, anchor: .bottom)
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
		if text.isEmpty {
			return rows
		}
		let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
		let max = lines.count - 1
		for (i, line) in lines.enumerated() {
			let content = String(line.trimmingCharacters(in: .whitespaces))
			if i == 0 && content.isEmpty {
				continue;
			}
			rows.append(Row(id: i - max, text: content))
		}
		return rows
	}

	@ViewBuilder private func makeButtons(_ row: Row) -> some View {
		let buttons = buttonsPref ?? "r-i-f"
		if buttons.contains("r") {
			Button("Repeat", systemImage: "repeat", action: { again?(row.text) })
				.labelStyle(.iconOnly)
				.buttonStyle(.bordered)
				.font(.title)
				.disabled(interjecting || row.text.isEmpty)
		}
		if buttons.contains("i") {
			Button("Interject", systemImage: "quote.bubble", action: { edit?(row.text) })
				.labelStyle(.iconOnly)
				.buttonStyle(.bordered)
				.font(.title)
				.disabled(interjecting || row.text.isEmpty)
		}
		if buttons.contains("f") {
			Button("Favorite", systemImage: "star", action: { edit?(row.text) })
				.labelStyle(.iconOnly)
				.buttonStyle(.bordered)
				.font(.title)
				.disabled(interjecting || row.text.isEmpty)
		}
	}
}

#Preview {
	WhisperPastTextView(interjecting: makeBinding(false), model: PastTextModel(mode: .whisper, initialText: """
		line 1 that's short
		line 2 that's quite a bit longer than line 1

		line 3 that's even longer than line 2 which was itself longer than line 1 which is longer than an empty line
		line 4
	"""))
}

#Preview {
	WhisperPastTextView(interjecting: makeBinding(true), model: PastTextModel(mode: .whisper, initialText: """
  line 1 that's short
  line 2 that's quite a bit longer than line 1

  line 3 that's even longer than line 2 which was itself longer than line 1 which is longer than an empty line
  line 4
 """))
}
