// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI


struct ChoiceView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
	@Environment(\.dynamicTypeSize) private var dynamicTypeSize
	@AppStorage("whisper_tap_preference") private var whisperTapAction: String?
	@AppStorage("listen_tap_preference") private var listenTapAction: String?

	@Binding var mode: OperatingMode
	@Binding var magnify: Bool

    @State private var showSpeechProfile = false
	@State private var showFavorites = false
	@State private var showNoConnection = false
	@State private var showSharingSheet = false
    @FocusState private var nameEdit: Bool

    var body: some View {
		VStack(spacing: 40) {
			Button(action: {
				mode = .whisper
			}) {
				Text("Speak")
					.foregroundColor(.white)
					.font(FontSizes.fontFor(FontSizes.minTextSize))
					.fontWeight(.bold)
					.frame(width: choiceButtonWidth() + 20, height: choiceButtonHeight() + 10, alignment: .center)
			}
			.background(Color.accentColor)
			.cornerRadius(15)
			Button(action: {
				showFavorites = true
			}) {
				Text("Edit Favorites")
					.foregroundColor(.white)
					.font(FontSizes.fontFor(FontSizes.minTextSize))
					.fontWeight(.bold)
					.frame(width: choiceButtonWidth(), height: choiceButtonHeight(), alignment: .center)
			}
			.background(Color.accentColor)
			.cornerRadius(15)
			.sheet(isPresented: $showFavorites) {
				FavoritesProfileView()
					.dynamicTypeSize(magnify ? .accessibility1 : dynamicTypeSize)
			}
			HStack(spacing: 50) {
				Button(action: {
					showSpeechProfile = true
				}) {
					Text("Speech Settings")
						.foregroundColor(.white)
						.font(FontSizes.fontFor(FontSizes.minTextSize))
						.fontWeight(.bold)
						.frame(width: choiceButtonWidth(), height: choiceButtonHeight(), alignment: .center)
				}
				.background(Color.accentColor)
				.cornerRadius(15)
				.sheet(isPresented: $showSpeechProfile) {
					SpeechProfileView()
						.dynamicTypeSize(magnify ? .accessibility1 : dynamicTypeSize)
				}
				Button(action: {
					UIApplication.shared.open(settingsUrl)
				}) {
					Text("App Settings")
						.foregroundColor(.white)
						.font(FontSizes.fontFor(FontSizes.minTextSize))
						.fontWeight(.bold)
						.frame(width: choiceButtonWidth(), height: choiceButtonHeight(), alignment: .center)
				}
				.background(Color.accentColor)
				.cornerRadius(15)
			}
			VStack (spacing: 25) {
				Button(action: {
					UIApplication.shared.open(PreferenceData.instructionSite())
				}) {
					Text("How To Use")
						.foregroundColor(.white)
						.font(FontSizes.fontFor(FontSizes.minTextSize))
						.fontWeight(.bold)
						.frame(width: choiceButtonWidth(), height: choiceButtonHeight(), alignment: .center)
				}
				.background(Color.accentColor)
				.cornerRadius(15)
				HStack {
					Button("About", action: {
						UIApplication.shared.open(PreferenceData.aboutSite())
					})
					.font(FontSizes.fontFor(FontSizes.minTextSize))
					.frame(width: choiceButtonWidth(), alignment: .center)
					Spacer()
					Button("Support", action: {
						UIApplication.shared.open(PreferenceData.supportSite())
					})
					.font(FontSizes.fontFor(FontSizes.minTextSize))
					.frame(width: choiceButtonWidth(), alignment: .center)
				}
				.frame(width: aboutSupportWidth())
			}
		}
    }

	private func aboutSupportWidth() -> CGFloat {
		return 350
	}
	private func choiceButtonWidth() -> CGFloat {
		return magnify ? 300 : 200
	}
	private func choiceButtonHeight() -> CGFloat {
		return magnify ? 77 : 45
	}
}

#Preview {
	ChoiceView(mode: makeBinding(.ask), magnify: makeBinding(false))
}
