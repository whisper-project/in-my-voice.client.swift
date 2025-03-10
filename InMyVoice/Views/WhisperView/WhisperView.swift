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

	@AppStorage("interjection_prefix_preference") private var interjectionPrefix: String?
	@AppStorage("interjection_alert_preference") private var interjectionAlert: String?

    @State private var liveText: String = ""
	@State private var pendingLiveText: String = ""
    @FocusState private var focusField: String?
    @StateObject private var model: WhisperViewModel
	@State private var size = PreferenceData.fontSize
	@State private var magnify: Bool = PreferenceData.useLargeFontSizes
	@State private var interjecting: Bool = false
	@State private var editFavorites: Bool = false
	@State private var editFavoritesFavorite: Favorite? = nil
	@State private var editFavoritesGroup: FavoritesGroup? = nil
	@State private var interjectionPrefixOverride: String?
	@State private var group: FavoritesGroup = PreferenceData.currentFavoritesGroup
	@State private var showFavorites: Bool = PreferenceData.showFavorites
	@State private var confirmStop: Bool = false
	@State private var inBackground: Bool = false
	@State private var window: Window?
	@StateObject private var appStatus = AppStatus.shared
	@State private var viewHasRespondedToQuit = false

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
				.sheet(isPresented: $editFavorites, onDismiss: { editFavoritesFavorite = nil; editFavoritesGroup = nil }) {
					FavoritesProfileView(use: self.maybeFavorite, g: self.editFavoritesGroup, f: self.editFavoritesFavorite)
						.font(FontSizes.fontFor(size))
						.dynamicTypeSize(magnify ? .accessibility3 : dynamicTypeSize)
				}
			}
			.onChange(of: interjecting) {
				if interjecting {
					pendingLiveText = liveText
					liveText = interjectionPrefixOverride ?? PreferenceData.interjectionPrefix()
					interjectionPrefixOverride = nil
					model.playInterjectionSound()
				} else {
					if !liveText.isEmpty && liveText != PreferenceData.interjectionPrefix() {
						liveText = model.submitLiveText()
					}
					liveText = pendingLiveText
				}
			}
			.onChange(of: interjectionPrefix) { UserProfile.shared.settingsProfile.update() }
			.onChange(of: interjectionAlert) { UserProfile.shared.settingsProfile.update() }
			.onAppear {
				logger.log("WhisperView appeared")
				model.start()
				focusField = "liveText"
				SleepControl.shared.disable(reason: "In Whisper Session")
			}
			.onDisappear {
				SleepControl.shared.enable()
				logger.log("WhisperView disappeared")
				model.stop()
			}
			.onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification), perform: { _ in
				logger.log("Received notification that app will terminate")
				quitWhisperView()
			})
			.onChange(of: appStatus.appIsQuitting) {
				if appStatus.appIsQuitting {
					logger.log("App has been told to quit")
					quitWhisperView()
				}
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

	private func maybeFavorite(_ f: Favorite? = nil) {
		editFavorites = false
		if let f = f {
			model.repeatLine(f.text)
		}
	}

	private func createFavorite(_ text: String, _ fs: [Favorite]) {
		if fs.isEmpty {
			let f = UserProfile.shared.favoritesProfile.newFavorite(text: text)
			editFavoritesFavorite = f
			editFavorites = true
		} else if fs.count == 1 {
			editFavoritesFavorite = fs[0]
			editFavorites = true
		} else {
			let g = UserProfile.shared.favoritesProfile.newGroup(name: "Duplicates")
			for f in fs { g.add(f) }
			editFavoritesGroup = g
			editFavorites = true
		}
	}

	private func doEditFavorites() {
		editFavorites = true
	}

	@ViewBuilder private func foregroundView(_ geometry: GeometryProxy) -> some View {
		WhisperControlView(size: $size,
						   status: $model.showStatusDetail,
						   magnify: $magnify,
						   interjecting: $interjecting,
						   showFavorites: $showFavorites,
						   group: $group,
						   maybeStop: maybeStop,
						   playSound: model.playSound,
						   repeatSpeech: model.repeatLine,
						   editFavorites: doEditFavorites,
						   clearTyping: clearTyping)
			.padding(EdgeInsets(top: whisperViewTopPad, leading: sidePad, bottom: 0, trailing: sidePad))
		if showFavorites {
			if isOnPhone() {
					FavoritesUseView(use: maybeFavorite, group: $group)
					.font(FontSizes.fontFor(size))
					.dynamicTypeSize(magnify ? .accessibility3 : dynamicTypeSize)
					.frame(maxWidth: geometry.size.width,
						   maxHeight: geometry.size.height * pastTextProportion,
						   alignment: .bottomLeading)
					.border(colorScheme == .light ? lightPastBorderColor : darkPastBorderColor, width: 2)
					.padding(EdgeInsets(top: 0, leading: sidePad, bottom: 0, trailing: sidePad))
			} else {
				HStack(spacing: 2) {
					WhisperPastTextView(interjecting: $interjecting,
										model: model.pastText,
										again: model.repeatLine,
										edit: startInterjection,
										favorite: createFavorite)
					.font(FontSizes.fontFor(size))
					.textSelection(.enabled)
					.foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
					.padding(innerPad)
					.border(colorScheme == .light ? lightPastBorderColor : darkPastBorderColor, width: 2)
					.dynamicTypeSize(magnify ? .accessibility3 : dynamicTypeSize)
					FavoritesUseView(use: maybeFavorite, group: $group)
						.font(FontSizes.fontFor(size))
						.dynamicTypeSize(magnify ? .accessibility3 : dynamicTypeSize)
						.frame(maxWidth: geometry.size.width * 1/3)
						.border(colorScheme == .light ? lightPastBorderColor : darkPastBorderColor, width: 2)
				}
				.frame(maxWidth: geometry.size.width,
					   maxHeight: geometry.size.height * pastTextProportion,
					   alignment: .bottomLeading)
				.padding(EdgeInsets(top: 0, leading: sidePad, bottom: 0, trailing: sidePad))
			}
		} else {
			WhisperPastTextView(interjecting: $interjecting,
								model: model.pastText,
								again: model.repeatLine,
								edit: startInterjection,
								favorite: createFavorite)
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
		}
		WhisperStatusTextView(model: model)
			.popover(isPresented: $model.showStatusDetail) {
				ListenersView(model: model)
			}
		TextEditor(text: $liveText)
			.font(FontSizes.fontFor(size))
			.truncationMode(.head)
			.onChange(of: liveText) { old, new in
				if interjecting && new == old + "\n" {
					liveText = old
					DispatchQueue.main.async { interjecting = false }
				} else {
					liveText = model.updateLiveText(old: old, new: new)
				}
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

	private func startInterjection(_ text: String) {
		guard !interjecting else {
			// Can't interject in the middle of an interjection
			return
		}
		interjectionPrefixOverride = text
		interjecting = true
	}

	private func clearTyping() {
		liveText = ""
	}

	private func quitWhisperView() {
		guard !viewHasRespondedToQuit else {
			logger.log("Whisper view is already terminating")
			return
		}
		logger.warning("Whisper view is terminating in response to quit signal")
		viewHasRespondedToQuit = true
		model.stop()
	}

	private func isOnPhone() -> Bool {
		return UIDevice.current.userInterfaceIdiom == .phone
	}
}

#Preview {
	WhisperView(mode: makeBinding(.whisper), conversation: UserProfile.shared.whisperProfile.fallback)
}
