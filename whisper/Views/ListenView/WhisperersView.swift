// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import CoreBluetooth
import SwiftUI

struct WhisperersView: View {
    @Environment(\.colorScheme) var colorScheme
    
    @ObservedObject var model: ListenViewModel

    var body: some View {
		if let candidate = model.whisperer {
			let (remote, info) = (candidate.remote, candidate.info)
			let sfname = remote.kind == .local ? "personalhotspot" : "network"
			Text("\(Image(systemName: sfname)) Listening to \(info.username) in conversation \(info.conversationName)")
				.lineLimit(nil)
				.font(FontSizes.fontFor(FontSizes.minTextSize + 2))
				.foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
				.padding()
		} else if !model.invites.isEmpty {
			VStack(alignment: .leading, spacing: 20) {
				ForEach(model.invites.map(Row.init)) { row in
					VStack(spacing: 5) {
						row.legend
							.lineLimit(nil)
							.foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
					}
					HStack {
						Button("Accept") { model.acceptInvite(row.id) }
						Spacer()
						Button("Refuse") { model.refuseInvite(row.id) }
					}
					.buttonStyle(.borderless)
				}
			}
			.font(FontSizes.fontFor(FontSizes.minTextSize + 2))
			.padding()
		} else {
			Text("No Whisperer")
				.font(FontSizes.fontFor(FontSizes.minTextSize + 2))
				.foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
				.padding()
		}
    }

	final class Row: Identifiable {
		var id: String
		var legend: Text

		init(_ candidate: ListenViewModel.Candidate) {
			id = candidate.remote.id
			let sfname = candidate.remote.kind == .local ? "personalhotspot" : "network"
			legend = Text("\(Image(systemName: sfname)) Invite from \(candidate.info.username) to conversation \(candidate.info.conversationName)")
		}
	}
}

#Preview {
	WhisperersView(model: ListenViewModel(nil))
}
