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
	@State private var pendingLiveText: String = ""
    @FocusState private var focusField: String?
    @StateObject private var model: WhisperViewModel
	@State private var size = PreferenceData.sizeWhenWhispering
	@State private var magnify: Bool = PreferenceData.magnifyWhenWhispering
	@State private var interjecting: Bool = false
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
					ConnectionErrorButtons(mode: $mode, severity: model.connectionErrorSeverity)
				} message: {
					ConnectionErrorContent(severity: model.connectionErrorSeverity, message: model.connectionErrorDescription)
				}
			}
			.onChange(of: interjecting) {
				if interjecting {
					pendingLiveText = liveText
					liveText = PreferenceData.interjectionPrefix()
					model.playInterjectionSound()
				} else {
					if liveText != "" {
						liveText = model.submitLiveText()
					}
					liveText = pendingLiveText
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
		ControlView(size: $size, magnify: $magnify, interjecting: $interjecting, mode: .whisper, maybeStop: maybeStop, playSound: model.playSound, repeatSpeech: model.repeatLastLiveLine)
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
			.border(colorScheme == .light ? lightLiveBorderColor : darkLiveBorderColor, width: interjecting ? 8 : 2)
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
}

#Preview {
	WhisperView(mode: makeBinding(.whisper), conversation: UserProfile.shared.whisperProfile.fallback)
}
