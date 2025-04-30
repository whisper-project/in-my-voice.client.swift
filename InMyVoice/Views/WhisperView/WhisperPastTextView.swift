// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct WhisperPastTextView: View {
	@Binding var interjecting: Bool
	@ObservedObject var model: PastTextModel
	var again: ((String?, Bool) -> Void)?
	var edit: ((String) -> Void)?
	var favorite: ((String, [Favorite]) -> Void)?

	@State private var rows: [Row] = []
	@AppStorage("history_buttons_preference") private var buttonsPref: String?
	@ObservedObject private var fp = FavoritesProfile.shared

    var body: some View {
		ScrollViewReader { proxy in
			List {
				ForEach(rows) { row in
					HStack(spacing: 5) {
						makeButtons(row)
						Text(.init(row.linked))
							.lineLimit(nil)
					}
					.id(row.id)
				}
			}
			.listStyle(.plain)
			.onChange(of: rows.count) {
				if !rows.isEmpty {
					proxy.scrollTo(0, anchor: .bottom)
				}
			}
		}
		.onChange(of: fp.timestamp, updateRows)
		.onChange(of: model.pastText, initial: true, updateRows)
    }

	private func updateRows() {
		rows = makeRows()
	}

	private struct Row: Identifiable {
		let id: Int
		let raw: String
		let linked: String
		let favorites: [Favorite]
	}

	private func makeRows() -> [Row] {
		var rows: [Row] = []
		if !model.pastText.isEmpty {
			let (raw: rawLines, linked: linkedLines) = model.getLines()
			let max = rawLines.count - 1
			for i in 0...max {
				let hidden = rawLines[i]
				let shown = String(linkedLines[i].trimmingCharacters(in: .whitespaces))
				let favorites = fp.lookupFavorite(text: hidden)
				rows.append(Row(id: i - max, raw: hidden, linked: shown, favorites: favorites))
			}
		}
		return rows
	}

	@ViewBuilder private func makeButtons(_ row: Row) -> some View {
		if row.linked.isEmpty {
			EmptyView()
		} else {
			let buttons = buttonsPref ?? "r-i-f"
			if buttons.contains("r") {
				Button("Repeat", systemImage: "repeat", action: { again?(row.raw, !row.favorites.isEmpty) })
					.labelStyle(.iconOnly)
					.buttonStyle(.bordered)
					.disabled(interjecting || row.linked.isEmpty)
			}
			if buttons.contains("i") {
				Button("Interject", systemImage: "quote.bubble", action: { edit?(row.raw) })
					.labelStyle(.iconOnly)
					.buttonStyle(.bordered)
					.disabled(interjecting || row.linked.isEmpty)
			}
			if buttons.contains("f") {
				Button("Favorite", systemImage: row.favorites.isEmpty ? "star": "star.fill", action: {
					favorite?(row.raw, row.favorites)
				})
				.labelStyle(.iconOnly)
				.buttonStyle(.bordered)
				.disabled(interjecting || row.linked.isEmpty)
			}
		}
	}
}
