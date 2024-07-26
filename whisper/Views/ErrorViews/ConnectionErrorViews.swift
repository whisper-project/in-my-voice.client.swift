// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct ConnectionErrorButtons: View {
	@Binding var mode: OperatingMode
	let severity: TransportErrorSeverity

    var body: some View {
		switch severity {
		case .temporary:
			Button("Yes") { mode = .ask }
			Button("No") { }
		case .settings:
			Button("Yes") {
				UIApplication.shared.open(settingsUrl)
			}
			Button("No") { }
		case .report:
			Button("Yes") {
				UIApplication.shared.open(supportSite)
			}
			Button("No") {}
		case .upgrade:
			Button("Yes") {
				mode = .ask
				let url = URL(string: "itms-apps://apps.apple.com/us/app/whisper-talk-without-voice/id6446479064")!
				UIApplication.shared.open(url)
			}
			Button("No") { }
		case .endSession:
			Button("OK") { mode = .ask }
		case .relaunch:
			Button("Relaunch") {
				mode = .ask
				restartApplication()
			}
		case .reinstall:
			Button("Reinstall") {
				mode = .ask
				let url = URL(string: "itms-apps://apps.apple.com/us/app/whisper-talk-without-voice/id6446479064")!
				UIApplication.shared.open(url)
				exit(0)
			}
		}
    }
}

struct ConnectionErrorContent: View {
	let severity: TransportErrorSeverity
	let message: String

	var body: some View {
		switch severity {
		case .temporary:
			Text("A temporary error occured: \(message)\n\nWould you like to restart this session?")
		case .settings:
			Text("An error occurred: \(message)\n\nWould you like to fix this in Settings?")
		case .report:
			Text("An error occurred: \(message)\n\nWould you like to report this to the developer?")
		case .upgrade:
			Text("You are using an out-of-date version of Whisper. Your Listeners are not. This may break your connection.\n\nDo you want to upgrade your app?")
		case .endSession:
			Text("A communication error has ended your session: \(message)\n\nPlease start a new session")
		case .relaunch:
			Text("This app encountered an error and must be relaunched: \(message)\n\nRelaunch when ready")
		case .reinstall:
			Text("This app encountered an error and must be deleted and reinstalled: \(message)\n\nPlease delete the app and reinstall it from the App Store")
		}
	}
}
