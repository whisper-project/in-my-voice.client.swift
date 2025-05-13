// Copyright 2025 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

let privacyText = """
	The In My Voice app does not collect any data from your usage of the app \
	unless you voluntarily participate in a research study (see below). \
	If you choose to participate in a research study, data about your usage \
	is collected and made available to the study administrators for their \
	research purposes. Contact your study administrators for details of \
	exactly what data is collected and how it is used.
	"""

struct PrivacyView: View {
#if targetEnvironment(macCatalyst)
	@Environment(\.dismiss) private var dismiss
#endif
	@AppStorage("in_study") private var inStudy: Bool = PreferenceData.inStudy

	var speech: () -> Void

	@State private var wantsToParticipateInStudy: Bool = PreferenceData.inStudy

	var body: some View {
		NavigationView {
			Form {
				Text(privacyText)
				Toggle("Are you participating in a research study?", isOn: $wantsToParticipateInStudy)
					.disabled(inStudy)
				if wantsToParticipateInStudy {
					Section(header: Text("Study Participation Details")) {
						StudyIdView(inStudy: $inStudy, speech: speech)
					}
				}
			}
			.navigationTitle("Data Collection and Privacy")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
#if targetEnvironment(macCatalyst)
				ToolbarItem(placement: .topBarLeading) {
					Button(action: { dismiss() }, label: { Text("Close") } )
				}
#endif
			}
		}
		.onChange(of: inStudy, initial: true) {
			wantsToParticipateInStudy = inStudy
		}
	}
}
