// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI
import SwiftUIWindowBinder


struct ChoiceView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
	@Environment(\.dynamicTypeSize) private var dynamicTypeSize
	@AppStorage("whisper_tap_preference") private var whisperTapAction: String?
	@AppStorage("listen_tap_preference") private var listenTapAction: String?
	@AppStorage("main_view_large_sizes_setting") private var useLargeSizes: Bool = false

	@Binding var mode: OperatingMode

    @State private var showSpeechProfile = false
	@State private var showFavorites = false
	@State private var showNoConnection = false
	@State private var showSharingSheet = false
    @FocusState private var nameEdit: Bool
	@State private var window: Window?

    let nameWidth = CGFloat(350)
    let nameHeight = CGFloat(105)
    let choiceButtonWidth = CGFloat(200)
    let choiceButtonHeight = CGFloat(45)

    var body: some View {
		VStack(spacing: 40) {
			Button(action: {
				mode = .whisper
			}) {
				Text("Speak")
					.foregroundColor(.white)
					.fontWeight(.bold)
					.frame(width: choiceButtonWidth, height: choiceButtonHeight, alignment: .center)
			}
			.background(Color.accentColor)
			.cornerRadius(15)
			Button(action: {
				showSpeechProfile = true
			}) {
				Text("Speech Settings")
					.foregroundColor(.white)
					.fontWeight(.bold)
					.frame(width: choiceButtonWidth, height: choiceButtonHeight, alignment: .center)
			}
			.background(Color.accentColor)
			.cornerRadius(15)
			.sheet(isPresented: $showSpeechProfile) {
				SpeechProfileView()
					.dynamicTypeSize(useLargeSizes ? .accessibility1 : dynamicTypeSize)
			}
			Button(action: {
				showFavorites = true
			}) {
				Text("Favorites Settings")
					.foregroundColor(.white)
					.fontWeight(.bold)
					.frame(width: choiceButtonWidth, height: choiceButtonHeight, alignment: .center)
			}
			.background(Color.accentColor)
			.cornerRadius(15)
			.sheet(isPresented: $showFavorites) {
				FavoritesProfileView()
					.dynamicTypeSize(useLargeSizes ? .accessibility1 : dynamicTypeSize)
			}
			Button(action: {
				UIApplication.shared.open(settingsUrl)
			}) {
				Text("App Settings")
					.foregroundColor(.white)
					.fontWeight(.bold)
					.frame(width: choiceButtonWidth, height: choiceButtonHeight, alignment: .center)
			}
			.background(Color.accentColor)
			.cornerRadius(15)
			VStack (spacing: 25) {
				Button(action: {
					UIApplication.shared.open(PreferenceData.instructionSite())
				}) {
					Text("How To Use")
						.foregroundColor(.white)
						.fontWeight(.bold)
						.frame(width: choiceButtonWidth, height: choiceButtonHeight, alignment: .center)
				}
				.background(Color.accentColor)
				.cornerRadius(15)
				HStack {
					Button("About", action: {
						UIApplication.shared.open(PreferenceData.aboutSite())
					})
					.frame(width: choiceButtonWidth, alignment: .center)
					Spacer()
					Button("Support", action: {
						UIApplication.shared.open(PreferenceData.supportSite())
					})
					.frame(width: choiceButtonWidth, alignment: .center)
				}
				.frame(width: nameWidth)
			}
		}
    }
}

#Preview {
    ChoiceView(mode: makeBinding(.ask))
}
