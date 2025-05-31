// Copyright 2025 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct ElevenLabsUsageView: View {
	enum ValidationState {
		case validating
		case timeout
	}

	@State private var validationState: ValidationState = .timeout

	@StateObject private var elevenLabs = ElevenLabs.shared

	var body: some View {
		if let info = ElevenLabs.shared.usageData {
				Text(LocalizedStringKey(Self.usageMessage(info)))
			} else {
			switch validationState {
			case .validating:
				ProgressView("Fetching usage data...")
					.onAppear {
						ElevenLabs.shared.downloadUsage {
							self.validationState = .timeout
						}
					}
			case .timeout:
				Text("Checking your ElevenLabs usage. If it doesn't appear soon, you can try again.")
				Button("Try again") {
					validationState = .validating
				}
			}
		}
		if elevenLabs.usageCutoff {
			Text(LocalizedStringKey(Self.cutoffMessage))
		}
    }

	static let cutoffMessage = """
				Because you are so close to your usage limit, all speech will be generated \
				with your chosen Apple voice until your next allotment from ElevenLabs is available.
				"""

	static func usageMessage(_ info: AccountInfo) -> String {
		let pct = info.usedChars * 100 / info.limitChars
		let renewDate = Date(timeIntervalSince1970: TimeInterval(info.nextRenew))
		let formatter = DateFormatter()
		formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
		let renewString = formatter.string(from: renewDate)
		let msg1 = "You have used \(info.usedChars.formatted()) characters (\(pct)%) of your allotted \(info.limitChars.formatted())."
		let msg2 = "You will receive a new allotment on \(renewString)."
		return msg1 + " " + msg2
	}
}

#Preview {
    ElevenLabsUsageView()
}
