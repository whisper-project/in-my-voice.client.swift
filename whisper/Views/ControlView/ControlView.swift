// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct ControlView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var size: FontSizes.FontSize
    @Binding var magnify: Bool
	@Binding var interjecting: Bool
	let mode: OperatingMode
	var maybeStop: (() -> Void)? = nil
    var playSound: (() -> Void)? = nil
	var repeatSpeech: ((String?) -> Void)? = nil
	var editFavorites: (() -> Void)? = nil
	var toggleFavorites: (() -> Void)? = nil

    @State var alertSound = PreferenceData.alertSound
    @State var speaking: Bool = false

    var body: some View {
		HStack(alignment: .center) {
            maybeAlarmButton()
            speechButton()
			maybeRepeatButton()
			maybeInterjectingButton()
			maybeFavoritesButton()
            maybeFontSizeButtons()
            maybeFontSizeToggle()
			Button(action: { maybeStop?() }) {
                stopButtonLabel()
            }
            .background(Color.accentColor)
            .cornerRadius(15)
        }
        .dynamicTypeSize(.large)
        .font(FontSizes.fontFor(FontSizes.minTextSize))
        .onAppear {
            speaking = mode == .listen ? PreferenceData.speakWhenListening : PreferenceData.speakWhenWhispering
        }
    }
    
	@ViewBuilder private func speechButton() -> some View {
		Button {
			speaking.toggle()
			if mode == .listen {
				PreferenceData.speakWhenListening = speaking
			} else {
				PreferenceData.speakWhenWhispering = speaking
			}
		} label: {
			Image(speaking ? "voice-over-on" : "voice-over-off")
				.renderingMode(.template)
				.resizable()
				.padding(5)
				.frame(width: 50, height: 50)
				.border(colorScheme == .light ? .black : .white, width: 1)
		}
		Spacer()
	}

	@ViewBuilder private func maybeRepeatButton() -> some View {
		if mode == .listen {
			EmptyView()
		} else {
			Button {
				repeatSpeech?(nil)
			} label: {
				Image("repeat-speech")
					.renderingMode(.template)
					.resizable()
					.padding(5)
					.frame(width: 50, height: 50)
					.border(colorScheme == .light ? .black : .white, width: 1)
			}
			Spacer()
		}
	}

	@ViewBuilder private func maybeInterjectingButton() -> some View {
		if mode == .listen {
			EmptyView()
		} else {
			Button {
				interjecting.toggle()
			} label: {
				Image(interjecting ? "interjecting" : "not-interjecting")
					.renderingMode(.template)
					.resizable()
					.padding(5)
					.frame(width: 50, height: 50)
					.border(colorScheme == .light ? .black : .white, width: 1)
			}
			Spacer()
		}
	}

	@ViewBuilder private func maybeFavoritesButton() -> some View {
		if mode == .listen {
			EmptyView()
		} else {
			Button {
				editFavorites?()
			} label: {
				Image(systemName: "star")
					.renderingMode(.template)
					.resizable()
					.padding(5)
					.frame(width: 50, height: 50)
					.border(colorScheme == .light ? .black : .white, width: 1)
			}
			Spacer()
		}
	}

    @ViewBuilder private func maybeAlarmButton() -> some View {
        if mode == .listen {
            EmptyView()
        } else {
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
                buttonImage(alertSound + "-icon", pad: 5)
            } primaryAction: {
                playSound?()
            }
            Spacer()
        }
    }

    private func buttonImage(_ name: String, pad: CGFloat = 0) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .padding(pad)
            .frame(width: 50, height: 50)
            .border(colorScheme == .light ? .black : .white, width: 1)
    }
    
    @ViewBuilder private func maybeFontSizeButtons() -> some View {
        if isOnPhone() && mode == .whisper {
            EmptyView()
        } else {
            Button {
                self.size = FontSizes.nextTextSmaller(self.size)
				if mode == .listen {
					PreferenceData.sizeWhenListening = self.size
				} else {
					PreferenceData.sizeWhenWhispering = self.size
				}
            } label: {
                buttonImage("font-down-button")
            }
            .disabled(size == FontSizes.minTextSize)
            Button {
                self.size = FontSizes.nextTextLarger(self.size)
				if mode == .listen {
					PreferenceData.sizeWhenListening = self.size
				} else {
					PreferenceData.sizeWhenWhispering = self.size
				}
            } label: {
                buttonImage("font-up-button")
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
				if mode == .listen {
					PreferenceData.magnifyWhenListening = magnify
				} else {
					PreferenceData.magnifyWhenWhispering = magnify
				}
			}
            .frame(maxWidth: 105)
            Spacer()
        }
    }

    private func stopButtonLabel() -> some View {
        Text(isOnPhone() ? "Stop" : mode == .listen ? "Stop Listening" : "Stop Whispering")
            .foregroundColor(.white)
            .font(.body)
            .fontWeight(.bold)
            .padding(10)
    }

    private func isOnPhone() -> Bool {
        return UIDevice.current.userInterfaceIdiom == .phone
    }
}

struct ControlView_Previews: PreviewProvider {
    static let options: [(Int, Bool, OperatingMode)] = [
        (FontSizes.minTextSize, false, .listen),
        (FontSizes.minTextSize + 2, false, .listen),
        (FontSizes.maxTextSize, false, .listen),
        (FontSizes.minTextSize, true, .listen),
        (FontSizes.maxTextSize, true, .listen),
        (FontSizes.minTextSize, false, .whisper),
        (FontSizes.minTextSize + 2, false, .whisper),
        (FontSizes.maxTextSize, false, .whisper),
        (FontSizes.minTextSize, true, .whisper),
        (FontSizes.maxTextSize, true, .whisper),
    ]
    static func sizeB(_ i: Int) -> Binding<Int> {
        return Binding(
            get: { options[i].0 },
            set: { _ = $0 })
    }

    static func magnifyB(_ i: Int) -> Binding<Bool> {
        return Binding(
            get: { options[i].1 },
            set: { _ = $0 })
    }

    static func modeB(_ i: Int) -> OperatingMode {
        return options[i].2
    }

	static func interjectingB(_ i: Int) -> Binding<Bool> {
		return Binding(get: { i % 2 == 0 }, set: { _ = $0 })
	}

    static var previews: some View {
        VStack {
            ForEach(0 ..< 10) {
				ControlView(size: sizeB($0), magnify: magnifyB($0), interjecting: interjectingB($0), mode: modeB($0))
            }
        }
    }
}
