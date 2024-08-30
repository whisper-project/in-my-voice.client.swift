// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct TranscriptData: Codable {
	var id: String			// transcript ID
	var startTime: Int64	// start date in epoch ms
	var duration: Int32		// duration in epoch ms
	var length: Int32		// length of transcript
}

struct WhisperTranscriptView: View {
#if targetEnvironment(macCatalyst)
	@Environment(\.dismiss) private var dismiss
#endif

	let conversation: WhisperConversation
	@Binding var transcripts: [TranscriptData]?
	@Binding var fetchStatus: Int

	let supportSite = URL(string: "https://clickonetwo.github.io/whisper/support.html")!

    var body: some View {
		Form {
			switch fetchStatus {
			case 0:
				Section("Fetch of transcripts in progress...") {
					EmptyView()
				}
			case -1:
				Section("Can't reach the server...\nPlease try again later") {
					EmptyView()
				}
			case 1:
				if let trs = transcripts, trs.count > 0 {
					List {
						ForEach(makeRows(trs)) { row in
							HStack {
								Text(row.description).lineLimit(nil)
								Spacer(minLength: 20)
								Link(destination: row.url) {
									Text(Image(systemName: "eyeglasses"))
								}
								Spacer().frame(width: 30)
								ShareLink("", item: row.url)
							}
							.buttonStyle(.borderless)
						}
					}
				} else {
					Section("No transcripts from the past week") {
						EmptyView()
					}
				}
			default:
				Link("Internal error, please report a bug!", destination: supportSite)
			}
		}
		.navigationTitle("Transcripts of \(conversation.name)")
		.navigationBarTitleDisplayMode(.inline)
    }

	struct Row: Identifiable {
		let id: Int
		let description: String
		let url: URL
	}

	func makeRows(_ trs: [TranscriptData]) -> [Row] {
		var i = 0
		let makeRow: (TranscriptData) -> Row = { tr in
			let start = Date(timeIntervalSince1970: Double(tr.startTime)/1000).formatted(date: .abbreviated, time: .shortened)
			let interval = TimeInterval(Double(tr.duration)/1000)
			let formatter = DateComponentsFormatter()
			formatter.unitsStyle = .brief
			let duration = {
				if interval < 60 {
					formatter.allowedUnits = [.minute, .second]
					if let result = formatter.string(from: interval) {
						return result
					} else {
						return "less than a minute"
					}
				} else if interval < 60 * 60 * 24 {
					formatter.allowedUnits = [.hour, .minute]
					if let result = formatter.string(from: interval) {
						return result
					} else {
						return "several hours"
					}
				} else {
					formatter.allowedUnits = [.day, .hour]
					if let result = formatter.string(from: interval) {
						return result
					} else {
						return "more than a day"
					}
				}
			}()
			let description = "\(start), lasted \(duration), \(tr.length) chars"
			let url = URL(string: "\(PreferenceData.whisperServer)/transcript/\(conversation.id)/\(tr.id)")!
			let row = Row(id: i, description: description, url: url)
			i += 1
			return row
		}
		return trs.map(makeRow)
	}
}
