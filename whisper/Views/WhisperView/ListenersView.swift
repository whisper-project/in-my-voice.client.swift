// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import CoreBluetooth
import SwiftUI

struct ListenersView: View {
    @Environment(\.colorScheme) var colorScheme
    
    @ObservedObject var model: WhisperViewModel
    
    var body: some View {
		VStack {
			Text(model.conversation.name)
				.font(FontSizes.fontFor(FontSizes.minTextSize + 2))
				.padding()
			if !model.invites.isEmpty {
				VStack(alignment: .leading, spacing: 20) {
					ForEach(model.invites.map(Row.init)) { row in
						VStack {
							row.legend
								.lineLimit(nil)
								.foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
							HStack {
								Button("Accept") { model.acceptRequest(row.id) }
								Spacer()
								Button("Refuse") { model.refuseRequest(row.id) }
							}
							.buttonStyle(.borderless)
						}
					}
				}
				Spacer(minLength: 20)
			}
			if model.listeners().isEmpty {
				Text("No Listeners")
			} else {
				VStack(alignment: .leading, spacing: 10) {
					ForEach(model.listeners()) { candidate in
						HStack(spacing: 0) {
							Text(candidate.info.username)
								.foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
							Image(systemName: candidate.remote.kind == .global ? "network" : "personalhotspot")
								.foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
							Spacer(minLength: 20)
							Button(action: { model.playSound(candidate) }, label: { Image(systemName: "speaker.wave.2") })
								.padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 20))
							Button(action: { model.dropListener(candidate) }, label: { Image(systemName: "delete.left") })
						}
						.buttonStyle(.borderless)
					}
				}
			}
		}
		.font(FontSizes.fontFor(FontSizes.minTextSize + 1))
		.padding()
    }
    
	final class Row: Identifiable {
		var id: String
		var legend: Text

		init(_ candidate: WhisperViewModel.Candidate) {
			id = candidate.remote.id
			let sfname = candidate.remote.kind == .local ? "personalhotspot" : "network"
			legend = Text("Request \(Image(systemName: sfname)) from \(candidate.info.username)")
		}
	}
}

#Preview {
	ListenersView(model: WhisperViewModel(UserProfile.shared.whisperDefault))
}
