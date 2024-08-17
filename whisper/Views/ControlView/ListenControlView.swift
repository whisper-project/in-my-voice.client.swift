// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct ListenControlView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var size: FontSizes.FontSize
    @Binding var magnify: Bool
	@Binding var interjecting: Bool
	var maybeStop: () -> Void

    @State var alertSound = PreferenceData.alertSound
    @State var speaking: Bool = false

    var body: some View {
		HStack(alignment: .center) {
            speechButton()
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
        .onAppear {
            speaking = PreferenceData.speakWhenListening
        }
    }
    
	@ViewBuilder private func speechButton() -> some View {
		Button {
			speaking.toggle()
			PreferenceData.speakWhenListening = speaking
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

    private func buttonImage(_ name: String, pad: CGFloat = 0) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .padding(pad)
            .frame(width: 50, height: 50)
            .border(colorScheme == .light ? .black : .white, width: 1)
    }
    
    @ViewBuilder private func maybeFontSizeButtons() -> some View {
        if isOnPhone() {
            EmptyView()
        } else {
            Button {
                self.size = FontSizes.nextTextSmaller(self.size)
				PreferenceData.sizeWhenListening = self.size
            } label: {
                buttonImage("font-down-button")
            }
            .disabled(size == FontSizes.minTextSize)
            Button {
                self.size = FontSizes.nextTextLarger(self.size)
				PreferenceData.sizeWhenListening = self.size
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
				PreferenceData.magnifyWhenListening = magnify
			}
            .frame(maxWidth: 105)
            Spacer()
        }
    }

    private func stopButtonLabel() -> some View {
        Text(isOnPhone() ? "Stop" : "Stop Listening")
            .foregroundColor(.white)
            .font(.body)
            .fontWeight(.bold)
            .padding(10)
    }

    private func isOnPhone() -> Bool {
        return UIDevice.current.userInterfaceIdiom == .phone
    }
}
