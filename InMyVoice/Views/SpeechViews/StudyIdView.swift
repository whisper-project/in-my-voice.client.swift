// Copyright 2025 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct StudyIdView: View {
	@Binding var inStudy: Bool

	enum ValidationState {
		case idle
		case validating
	}

	@State private var wantsOut: Bool = false
	@State private var studyId: String = ""
	@State private var state: ValidationState = .idle
	@State private var validationSucceeded: Bool?
	@State private var voiceName: String = ElevenLabs.voiceName

	@ObservedObject private var elevenLabs = ElevenLabs.shared

	var body: some View {
		if (inStudy) {
			switch state {
			case .validating:
				ProgressView()
			case .idle:
				if validationSucceeded ?? true {
					Text("Your study enrollment is confirmed. Your ElevenLabs voice settings have been provided by the study administrators. If you would like to change your settings, please work with the study administrators.")
					HStack(spacing: 5) {
						Text("Your ElevenLabs voice is named:")
						Text(voiceName)
					}
					.onChange(of: elevenLabs.timestamp, initial: true) {
						voiceName = ElevenLabs.voiceName
					}
					ElevenLabsUsageView()
				} else {
					Text("Sorry, a temporary problem prevented dropping you from the study. Please try again later.")
				}
				Button("Drop me from the study") {
					self.wantsOut = true
				}
				.alert("Confirmation", isPresented: $wantsOut, actions: {
					Button("No", role: .cancel) {}
					Button("Yes", role: .destructive) {
						state = .validating
						ServerProtocol.notifyLeaveStudy() { result in
							state = .idle
							validationSucceeded = result
							if result {
								inStudy = false
							}
						}
					}
				}, message: {
					Text("Do you really want to leave the study?\nThis will not remove your ElevenLabs voice settings.")
				})
			}
		} else {
			switch state {
			case .idle:
				if validationSucceeded ?? true {
					Text("To enroll in the study, enter your Unique Participant Number and click the button.")
				} else {
					Text("The Unique Participant Number you entered was not accepted. Please correct it and try again.")
				}
				HStack {
					TextField("Unique Participant Number", text: $studyId)
					Button("Validate UPN and Join Study") {
						ServerProtocol.notifyJoinStudy(studyId) { result in
							state = .idle
							validationSucceeded = result
						}
					}
				}
			case .validating:
				ProgressView()
			}
		}
	}
}

#Preview {
	StudyIdView(inStudy: makeBinding(true))
	StudyIdView(inStudy: makeBinding(false))
}
