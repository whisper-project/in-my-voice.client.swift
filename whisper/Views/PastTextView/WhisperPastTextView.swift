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
	var favorite: ((String, [Favorite]) -> Void)?

	@State private var rows: [Row] = []
	@AppStorage("history_buttons_preference") private var buttonsPref: String?
	@ObservedObject private var fp = UserProfile.shared.favoritesProfile

    var body: some View {
		ScrollViewReader { proxy in
			List {
				ForEach(rows) { row in
					HStack(spacing: 5) {
						makeButtons(row)
						Text(row.text)
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
		.onChange(of: fp.timestamp, updateFromProfile)
		.onChange(of: model.pastText, initial: true, updateFromProfile)
    }

	private func updateFromProfile() {
		rows = makeRows(model.pastText)
	}

	private struct Row: Identifiable {
		let id: Int
		let text: String
		let favorites: [Favorite]
	}

	private func makeRows(_ text: String) -> [Row] {
		var rows: [Row] = []
		if text.isEmpty {
			return rows
		}
		var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
		// remove empty first line
		if lines.first == "" {
			lines.removeFirst()
		}
		let max = lines.count - 1
		for (i, line) in lines.enumerated() {
			let content = String(line.trimmingCharacters(in: .whitespaces))
			let favorites = fp.lookupFavorite(text: content)
			rows.append(Row(id: i - max, text: content, favorites: favorites))
		}
		return rows
	}

	@ViewBuilder private func makeButtons(_ row: Row) -> some View {
		if row.text.isEmpty {
			EmptyView()
		} else {
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
				Button("Favorite", systemImage: row.favorites.isEmpty ? "star": "star.fill", action: {
					favorite?(row.text, row.favorites)
				})
				.labelStyle(.iconOnly)
				.buttonStyle(.bordered)
				.font(.title)
				.disabled(interjecting || row.text.isEmpty)
			}
		}
	}
}
