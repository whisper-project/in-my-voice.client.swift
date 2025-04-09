// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI


struct ChoiceView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
	@Environment(\.dynamicTypeSize) private var dynamicTypeSize

	@Binding var mode: OperatingMode
	@Binding var magnify: Bool

	@State private var orientation = UIDevice.current.orientation
    @State private var showSpeechProfile = false
	@State private var showFavorites = false
	@State private var showNoConnection = false
	@State private var showSharingSheet = false
    @FocusState private var nameEdit: Bool

    var body: some View {
		if (platformInfo == "phone") {
			if (orientation == .portrait || orientation == .unknown) {
				VStack(spacing: stackSpacing()) {
					SpeakButton()
					EditFavoritesButton()
					SpeechSettingsButton()
					AppSettingsButton()
					HowToUseButton()
				}
				.onRotate { orientation = $0 }
			} else {
				VStack(spacing: stackSpacing()) {
					HStack(spacing: 20) {
						SpeakButton()
						centerBig(EditFavoritesButton)
					}
					HStack(spacing: 20) {
						centerBig(SpeechSettingsButton)
						centerBig(AppSettingsButton)
					}
					HowToUseButton()
				}
				.onRotate { orientation = $0 }
			}
		} else {
			VStack(spacing: stackSpacing()) {
				SpeakButton()
				EditFavoritesButton()
				HStack(spacing: 20) {
					SpeechSettingsButton()
					AppSettingsButton()
				}
				HowToUseButton()
			}
		}
    }

	@ViewBuilder private func SpeakButton() -> some View {
		Button(action: { mode = .whisper }) {
			Text("Speak")
				.foregroundColor(.white)
				.font(FontSizes.fontFor(FontSizes.minTextSize))
				.fontWeight(.bold)
				.frame(width: choiceButtonWidth() + 20, height: choiceButtonHeight() + 10, alignment: .center)
		}
		.background(Color.accentColor)
		.cornerRadius(15)
	}

	@ViewBuilder private func EditFavoritesButton() -> some View {
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
	}

	@ViewBuilder private func centerBig(_ view: () -> some View) -> some View {
		view()
			.frame(width: choiceButtonWidth() + 20, height: choiceButtonHeight() + 10, alignment: .center)
	}

	@ViewBuilder private func SpeechSettingsButton() -> some View {
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
	}

	@ViewBuilder private func AppSettingsButton() -> some View {
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

	@ViewBuilder private func HowToUseButton() -> some View {
		VStack (spacing: stackSpacing()) {
			Spacer().frame(height: 0)
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

	private func aboutSupportWidth() -> CGFloat {
		return 350
	}
	private func choiceButtonWidth() -> CGFloat {
		return magnify ? 240 : 200
	}
	private func choiceButtonHeight() -> CGFloat {
		return magnify ? 54 : 45
	}
	private func stackSpacing() -> CGFloat {
		return orientation == .portrait ? (magnify ? 20 : 40) : platformInfo == "phone" ? (magnify ? 10 : 20) : (magnify ? 20 : 40)
	}
}

#Preview {
	ChoiceView(mode: makeBinding(.ask), magnify: makeBinding(false))
}
