// Copyright 2025 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct SpeechSettingsView: View {
#if targetEnvironment(macCatalyst)
	@Environment(\.dismiss) private var dismiss
#endif
	@AppStorage("in_study") private var inStudy: Bool = PreferenceData.inStudy

	@State private var wantsToParticipateInStudy: Bool = PreferenceData.inStudy

	var body: some View {
		NavigationView {
			Form {
				Toggle("Are you participating in a research study?", isOn: $wantsToParticipateInStudy)
					.disabled(inStudy)
				if wantsToParticipateInStudy {
					Section(header: Text("Study Participation Details")) {
						StudyIdView(inStudy: $inStudy)
					}
				} else {
					Section(header: Text("ElevenLabs Speech Settings")) {
						ElevenLabsSettingsView()
					}
				}
				Section(header: Text("Apple Speech Settings")){
					AppleSettingsView()
				}
			}
			.onAppear(perform: ElevenLabs.shared.downloadUsage)
			.navigationTitle("Speech Settings")
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

#Preview {
    SpeechSettingsView()
}
