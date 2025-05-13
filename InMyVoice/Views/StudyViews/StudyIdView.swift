// Copyright 2025 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct StudyIdView: View {
	@Binding var inStudy: Bool
	var speech: () -> Void

	enum ValidationState {
		case idle
		case validating
	}

	@State private var studyId: String = ""
	@State private var upn: String = ""

	var body: some View {
		if (inStudy) {
			InStudyView(inStudy: $inStudy, speech: speech)
		} else {
			if studyId == "" {
				ChooseStudyView(studyId: $studyId)
			} else {
				ChooseUpnView(studyId: $studyId, upn: $upn)
			}
		}
	}

	struct InStudyView: View {
		@Binding var inStudy: Bool
		var speech: () -> Void

		@ObservedObject private var elevenLabs = ElevenLabs.shared

		@State private var apiKey: String = ElevenLabs.apiKey
		@State private var voiceName: String = ElevenLabs.voiceName
		@State private var wantsOut: Bool = false
		@State private var state: ValidationState = .idle
		@State private var validationSucceeded: Bool?

		var body: some View {
			switch state {
			case .validating:
				ProgressView()
			case .idle:
				if validationSucceeded ?? true {
					if apiKey == "" {
						Text("Your study enrollment is confirmed.")
							.onChange(of: elevenLabs.timestamp, initial: true) {
								apiKey = ElevenLabs.apiKey
								voiceName = ElevenLabs.voiceName
							}
						Button("Configure Speech Settings") {
							speech()
						}
					} else {
						Text("Your study enrollment is confirmed. Your initial ElevenLabs voice settings have been provided by the study administrators.")
						HStack(spacing: 5) {
							Text("Your ElevenLabs voice is named:")
							Text(voiceName)
						}
						.onChange(of: elevenLabs.timestamp, initial: true) {
							apiKey = ElevenLabs.apiKey
							voiceName = ElevenLabs.voiceName
						}
						ElevenLabsUsageView()
							.onAppear(perform: elevenLabs.downloadUsage)
						Button("Configure Speech Settings") {
							speech()
						}
					}
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
					Text("Do you really want to leave the study?")
				})
			}
		}
	}

	struct ChooseStudyView: View {
		@Binding var studyId: String

		@State private var studies: [String: String] = [:]
		@State private var chosenStudyId: String?
		@State private var state: ValidationState = .idle
		@State private var validationSucceeded: Bool?

		var body: some View {
			VStack(alignment: .leading) {
				switch state {
				case .validating:
					Text("Fetching the available studies...")
					ProgressView()
				case .idle:
					if validationSucceeded ?? true {
						if studies.isEmpty {
							Text("Sorry, but there are no studies currently available. Please try again later.")
							Button("Try Again") {
								updateStudies()
							}
						} else {
							Picker("Available Studies", selection: $chosenStudyId) {
								Text("(Choose a study)").tag(nil as String?)
								ForEach(studies.keys.sorted(), id: \.self) { studyName in
									Text(studyName).tag(self.studies[studyName])
								}
							}
							Button("Select this study") {
								studyId = chosenStudyId!
							}
							.disabled(chosenStudyId == nil)
						}
					} else {
						Text("Sorry, there was an error fetching the available studies. Please try again later.")
						Button("Try Again") {
							updateStudies()
						}
					}
				}
			}
			.onAppear(perform: updateStudies)
		}

		private func updateStudies() {
			state = .validating
			ServerProtocol.fetchStudies() { studies, ok in
				self.studies = studies
				self.validationSucceeded = ok
				self.state = .idle
			}
		}
	}

	struct ChooseUpnView: View {
		@Binding var studyId: String
		@Binding var upn: String

		@State private var state: ValidationState = .idle
		@State private var validationSucceeded: Bool?

		var body: some View {
			switch state {
			case .idle:
				if validationSucceeded ?? true {
					Text("To enroll in the study, enter your Unique Participant Number and click the button.")
				} else {
					Text("The Unique Participant Number you entered was not accepted. Please correct it and try again.")
				}
				TextField("Unique Participant Number", text: $upn)
					.autocorrectionDisabled(true)
					.textInputAutocapitalization(.none)
				HStack {
					Button("Validate UPN and Join Study") {
						ServerProtocol.notifyJoinStudy(studyId, upn) { result in
							state = .idle
							validationSucceeded = result
						}
					}
					.disabled(upn == "")
					Spacer()
					Button("Choose a Different Study") {
						studyId = ""
						upn = ""
					}
				}
			case .validating:
				ProgressView()
			}
		}
	}
}
