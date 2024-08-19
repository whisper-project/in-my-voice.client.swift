// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct WhisperControlView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var size: FontSizes.FontSize
    @Binding var magnify: Bool
	@Binding var interjecting: Bool
	@Binding var showFavorites: Bool
	@Binding var group: FavoritesGroup
	var maybeStop: () -> Void
    var playSound: () -> Void
	var repeatSpeech: (String?) -> Void
	var editFavorites: () -> Void

    @State private var alertSound = PreferenceData.alertSound
    @State private var speaking: Bool = false
	@State private var allGroups: [FavoritesGroup] = []
	@StateObject private var fp = UserProfile.shared.favoritesProfile

    var body: some View {
		HStack(alignment: .center) {
            alarmButton()
            speechButton()
			repeatButton()
			interjectingButton()
			favoritesButton()
            maybeFontSizeButtons()
            maybeFontSizeToggle()
			Button(action: { maybeStop() }) {
                stopButtonLabel()
            }
            .background(Color.accentColor)
            .cornerRadius(15)
        }
        .dynamicTypeSize(.large)
        .font(FontSizes.fontFor(FontSizes.minTextSize))
		.onChange(of: fp.timestamp, initial: true, updateFromProfile)
    }

	private func updateFromProfile() {
		speaking = PreferenceData.speakWhenWhispering
		allGroups = fp.allGroups()
	}

	@ViewBuilder private func alarmButton() -> some View {
		Menu {
			ForEach(PreferenceData.alertSoundChoices) { choice in
				Button {
					alertSound = choice.id
					PreferenceData.alertSound = choice.id
				} label: {
					Label(choice.name, image: choice.id + "-icon")
				}
			}
		} label: {
			buttonImage(name: alertSound + "-icon", pad: 5)
		} primaryAction: {
			playSound()
		}
		Spacer()
	}

	@ViewBuilder private func speechButton() -> some View {
		Button {
			speaking.toggle()
			PreferenceData.speakWhenWhispering = speaking
		} label: {
			buttonImage(name: speaking ? "voice-over-on" : "voice-over-off", pad: 5)
		}
		Spacer()
	}

	@ViewBuilder private func repeatButton() -> some View {
		Button {
			repeatSpeech(nil)
		} label: {
			buttonImage(name: "repeat-speech", pad: 5)
		}
		Spacer()
	}

	@ViewBuilder private func interjectingButton() -> some View {
		Button {
			interjecting.toggle()
		} label: {
			buttonImage(name: interjecting ? "interjecting" : "not-interjecting", pad: 5)
		}
		Spacer()
	}

	@ViewBuilder private func favoritesButton() -> some View {
		Menu {
			Button("All", action: { toggleShowFavorites(fp.allGroup) })
			ForEach(allGroups) { group in
				Button(action: { toggleShowFavorites(group) }, label: { Text(group.name) })
			}
			Button("Edit Favorites", action: { editFavorites() })
		} label: {
			buttonImage(systemName: showFavorites ? "star.fill" : "star", pad: 5)
		} primaryAction: {
			toggleShowFavorites()
		}
		Spacer()
	}

    @ViewBuilder private func maybeFontSizeButtons() -> some View {
        if isOnPhone() {
            EmptyView()
        } else {
            Button {
                self.size = FontSizes.nextTextSmaller(self.size)
				PreferenceData.sizeWhenWhispering = self.size
            } label: {
				buttonImage(name: "font-down-button", pad: 0)
            }
            .disabled(size == FontSizes.minTextSize)
            Button {
                self.size = FontSizes.nextTextLarger(self.size)
				PreferenceData.sizeWhenWhispering = self.size
            } label: {
				buttonImage(name: "font-up-button", pad: 0)
            }
            .disabled(size == FontSizes.maxTextSize)
            Spacer()
        }
    }
    
    @ViewBuilder private func maybeFontSizeToggle() -> some View {
        if isOnPhone() {
            EmptyView()
        } else {
            Toggle(isOn: $magnify) {
                Text("Large Sizes")
            }
			.onChange(of: magnify) {
				PreferenceData.magnifyWhenWhispering = magnify
			}
            .frame(maxWidth: 105)
            Spacer()
        }
    }

	private func toggleShowFavorites(_ group: FavoritesGroup? = nil) {
		if let group = group {
			self.group = group
			PreferenceData.currentFavoritesGroup = group
			if !showFavorites {
				showFavorites = true
				PreferenceData.showFavorites = true
			}
		} else {
			showFavorites.toggle()
			PreferenceData.showFavorites = showFavorites
		}
	}

    private func stopButtonLabel() -> some View {
        Text(isOnPhone() ? "Stop" : "Stop Whispering")
            .foregroundColor(.white)
            .font(.body)
            .fontWeight(.bold)
            .padding(10)
    }

	private func buttonImage(name: String, pad: CGFloat) -> some View {
		Image(name)
			.renderingMode(.template)
			.resizable()
			.padding(pad)
			.frame(width: 50, height: 50)
			.border(colorScheme == .light ? .black : .white, width: 1)
	}

	private func buttonImage(systemName: String, pad: CGFloat) -> some View {
		Image(systemName: systemName)
			.renderingMode(.template)
			.resizable()
			.padding(pad)
			.frame(width: 50, height: 50)
			.border(colorScheme == .light ? .black : .white, width: 1)
	}

    private func isOnPhone() -> Bool {
        return UIDevice.current.userInterfaceIdiom == .phone
    }
}
