// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI
import SwiftUIWindowBinder

struct WhisperView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.scenePhase) var scenePhase

    @Binding var mode: OperatingMode
    var conversation: WhisperConversation

    @State private var liveText: String = ""
    @FocusState private var focusField: String?
    @StateObject private var model: WhisperViewModel
	@State private var size = PreferenceData.sizeWhenWhispering
	@State private var magnify: Bool = PreferenceData.magnifyWhenWhispering
	@State private var confirmStop: Bool = false
	@State private var inBackground: Bool = false
	@State private var window: Window?

    init(mode: Binding<OperatingMode>, conversation: WhisperConversation) {
        self._mode = mode
        self.conversation = conversation
        self._model = StateObject(wrappedValue: WhisperViewModel(conversation))
    }

    var body: some View {
		WindowBinder(window: $window) {
			GeometryReader { geometry in
				VStack(spacing: 10) {
					if inBackground && platformInfo == "pad" {
						backgroundView(geometry)
					} else {
						foregroundView(geometry)
					}
				}
				.multilineTextAlignment(.leading)
				.lineLimit(nil)
				.alert("Confirm Stop", isPresented: $confirmStop) {
					Button("Stop") {
						mode = .ask
					}
					Button("Don't Stop") {
						focusField = "liveText"
					}
					if !UserProfile.shared.userPassword.isEmpty {
						Button("Change Device") {
							model.sendRestart()
							mode = .ask
						}
					}
				} message: {
					Text("Do you really want to stop \(mode == .whisper ? "whispering" : "listening")?")
				}
				.alert("Unexpected Error", isPresented: $model.connectionError) {
					errorButtons(model.connectionErrorSeverity, model.connectionErrorDescription)
				} message: {
					errorContent(model.connectionErrorSeverity, model.connectionErrorDescription)
				}
			}
			.onAppear {
				logger.log("WhisperView appeared")
				model.start()
				focusField = "liveText"
				UIApplication.shared.isIdleTimerDisabled = true
			}
			.onDisappear {
				UIApplication.shared.isIdleTimerDisabled = false
				logger.log("WhisperView disappeared")
				model.stop()
			}
			.onChange(of: window) {
				window?.windowScene?.title = "Whispering to \(conversation.name)"
			}
			.onChange(of: conversation.name) {
				window?.windowScene?.title = "Whispering to \(conversation.name)"
			}
			.onChange(of: scenePhase) {
				switch scenePhase {
				case .background:
					logger.log("Went to background")
					focusField = nil
					inBackground = true
					model.wentToBackground()
				case .inactive:
					logger.log("Went inactive")
				case .active:
					logger.log("Went to foreground")
					focusField = "liveText"
					inBackground = false
					model.wentToForeground()
				@unknown default:
					inBackground = false
					logger.error("Went to unknown phase: \(String(describing: scenePhase), privacy: .public)")
				}
			}
		}
    }

	private func maybeStop() {
		focusField = nil
		confirmStop = true
	}

	@ViewBuilder private func foregroundView(_ geometry: GeometryProxy) -> some View {
		ControlView(size: $size, magnify: $magnify, mode: .whisper, maybeStop: maybeStop, playSound: model.playSound)
			.padding(EdgeInsets(top: whisperViewTopPad, leading: sidePad, bottom: 0, trailing: sidePad))
		PastTextView(mode: .whisper, model: model.pastText)
			.font(FontSizes.fontFor(size))
			.textSelection(.enabled)
			.foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
			.padding(innerPad)
			.frame(maxWidth: geometry.size.width,
				   maxHeight: geometry.size.height * pastTextProportion,
				   alignment: .bottomLeading)
			.border(colorScheme == .light ? lightPastBorderColor : darkPastBorderColor, width: 2)
			.padding(EdgeInsets(top: 0, leading: sidePad, bottom: 0, trailing: sidePad))
			.dynamicTypeSize(magnify ? .accessibility3 : dynamicTypeSize)
		StatusTextView(text: $model.statusText, mode: .whisper, conversation: conversation)
			.onTapGesture {
				self.model.showStatusDetail = true
			}
			.popover(isPresented: $model.showStatusDetail) {
				ListenersView(model: model)
			}
		TextEditor(text: $liveText)
			.font(FontSizes.fontFor(size))
			.truncationMode(.head)
			.onChange(of: liveText) { old, new in
				self.liveText = model.updateLiveText(old: old, new: new)
			}
			.onSubmit {
				// shouldn't ever be used with a TextEditor,
				// but it was needed with a TextField with a vertical axis
				// when using a Magic Keyboard
				self.liveText = model.submitLiveText()
				focusField = "liveText"
			}
			.focused($focusField, equals: "liveText")
			.foregroundColor(colorScheme == .light ? lightLiveTextColor : darkLiveTextColor)
			.padding(innerPad)
			.frame(maxWidth: geometry.size.width,
				   maxHeight: geometry.size.height * liveTextProportion,
				   alignment: .topLeading)
			.border(colorScheme == .light ? lightLiveBorderColor : darkLiveBorderColor, width: 2)
			.padding(EdgeInsets(top: 0, leading: sidePad, bottom: whisperViewBottomPad, trailing: sidePad))
			.dynamicTypeSize(magnify ? .accessibility3 : dynamicTypeSize)
	}

	private func backgroundView(_ geometry: GeometryProxy) -> some View {
		VStack(alignment: .center) {
			Spacer()
			HStack {
				Spacer()
				Text("Whispering to \(conversation.name)")
					.font(.system(size: geometry.size.height / 5, weight: .bold))
					.lineLimit(nil)
					.multilineTextAlignment(.center)
					.foregroundColor(.white)
				Spacer()
			}
			Spacer()
		}
		.background(Color.accentColor)
		.ignoresSafeArea()
	}

	@ViewBuilder private func errorButtons(_ severity: TransportErrorSeverity, _ message: String) -> some View {
		switch severity {
		case .temporary:
			Button("Yes") { mode = .ask }
			Button("No") { }
		case .ignore:
			Button("Report") {
				UIApplication.shared.open(supportSite)
			}
			Button("Ignore") {}
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

	@ViewBuilder private func errorContent(_ severity: TransportErrorSeverity, _ message: String) -> some View {
		switch model.connectionErrorSeverity {
		case .temporary:
			Text("You are no longer connected to your Listeners. This may be temporary.\n\nWould you like to restart this session?")
		case .ignore:
			Text("A non-serious error occurred: \(message)\n\nWould you like to report this to the developer?")
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

#Preview {
	WhisperView(mode: makeBinding(.whisper), conversation: UserProfile.shared.whisperProfile.fallback)
}
