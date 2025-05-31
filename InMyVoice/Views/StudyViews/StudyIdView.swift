// Copyright 2025 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct StudyIdView: View {
	enum ValidationState {
		case idle
		case validating
	}

	@Binding var inStudy: String?
	var speech: () -> Void

	@State private var studies: [String: String] = [:]
	@State private var studyId: String = ""
	@State private var upn: String = ""
	@State private var joinedWithSettings: Bool? = nil

	var body: some View {
		if let studyName = inStudy {
			InStudyView(studyName: studyName, studyId: $studyId, joinedWithSettings: $joinedWithSettings, speech: speech)
		} else {
			if studyId == "" {
				ChooseStudyView(studies: $studies, studyId: $studyId)
			} else {
				ChooseUpnView(studies: $studies, studyId: $studyId, upn: $upn, joinedWithSettings: $joinedWithSettings)
			}
		}
	}

	struct InStudyView: View {
		var studyName: String
		@Binding var studyId: String
		@Binding var joinedWithSettings: Bool?
		var speech: () -> Void

		@ObservedObject private var elevenLabs = ElevenLabs.shared

		@State private var apiKey: String = ElevenLabs.apiKey
		@State private var voiceName: String = ElevenLabs.voiceName
		@State private var wantsOut: Bool = false
		@State private var state: ValidationState = .idle
		@State private var leftStudy: Bool? = nil

		var body: some View {
			switch state {
			case .validating:
				ProgressView()
			case .idle:
				if joinedWithSettings != nil {
					Text("Your enrollment in the \(studyName) study is confirmed.")
					if joinedWithSettings == true {
						Text("Your study administrators have provided ElevenLabs settings that will be shared among all your devices. You will need to configure your desired Apple speech settings on each device.")
					} else {
						Text("Your next step is to configure your Apple and ElevenLabs speech settings.")
					}
				} else if leftStudy == false {
					Text("Sorry, a temporary problem prevented dropping you from the study. Please try again later.")
				} else {
					Text("You are currently enrolled in the \(studyName) study.")
				}
				HStack {
					Button("Configure Speech Settings", action: speech)
					Spacer()
					Button("Drop me from the study") {
						self.wantsOut = true
					}
					.alert("Confirmation", isPresented: $wantsOut, actions: {
						Button("No", role: .cancel, action: {})
						Button("Yes", role: .destructive, action: leaveStudy)
					}, message: {
						Text("Do you really want to leave the study?")
					})
				}
				.buttonStyle(.borderless)
			}
		}

		func leaveStudy() {
			state = .validating
			leftStudy = nil
			ServerProtocol.notifyLeaveStudy() { success in
				DispatchQueue.main.async {
					self.state = .idle
					self.leftStudy = success
					if success {
						studyId = ""
						PreferenceData.inStudy = nil
					}
				}
			}
		}
	}

	struct ChooseStudyView: View {
		@Binding var studies: [String: String]
		@Binding var studyId: String

		@State private var chosenStudyId: String? = nil
		@State private var state: ValidationState = .idle
		@State private var validationSucceeded: Bool? = nil

		var body: some View {
			EmptyView()
				.onAppear(perform: updateStudies)
			switch state {
			case .validating:
				Text("Fetching the available studies...")
				ProgressView()
			case .idle:
				if validationSucceeded == nil {
					Text("Fetching the available studies...")
						.onAppear(perform: updateStudies)
				} else if validationSucceeded == true {
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
							chosenStudyId = nil
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

		func updateStudies() {
			state = .validating
			ServerProtocol.fetchStudies() { studies, ok in
				self.studies = studies
				self.validationSucceeded = ok
				self.state = .idle
			}
		}
	}

	struct ChooseUpnView: View {
		@Binding var studies: [String: String]
		@Binding var studyId: String
		@Binding var upn: String
		@Binding var joinedWithSettings: Bool?

		@State private var state: ValidationState = .idle
		@State private var validationSucceeded: Bool? = nil

		var body: some View {
			switch state {
			case .idle:
				if validationSucceeded ?? true {
					Text("To enroll in \(findName()), enter your Unique Participant Number and click the button.")
				} else {
					Text("The Unique Participant Number you entered for \(findName()) was not accepted. Please correct it and try again.")
				}
				TextField("Unique Participant Number", text: $upn)
					.autocorrectionDisabled(true)
					.textInputAutocapitalization(.none)
				HStack {
					Button("Validate UPN and Join Study", action: joinStudy)
						.disabled(upn == "")
					Spacer()
					Button("Choose a Different Study") {
						studyId = ""
						upn = ""
					}
					.disabled(studies.count == 1)
				}
				.buttonStyle(.borderless)
			case .validating:
				ProgressView()
			}
		}

		func findName() -> String {
			for (name, id) in studies {
				if id == studyId {
					return "the " + name + " study"
				}
			}
			return "the study"
		}

		func joinStudy() {
			state = .validating
			ServerProtocol.notifyJoinStudy(studyId, upn) { status in
				state = .idle
				switch status {
				case 200:
					joinedWithSettings = true
					validationSucceeded = true
					upn = ""
				case 204:
					joinedWithSettings = false
					validationSucceeded = true
					upn = ""
				default:
					validationSucceeded = false
				}
			}
		}
	}
}
