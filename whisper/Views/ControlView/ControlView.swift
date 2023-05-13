// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct ControlView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var size: FontSizes.FontSize
    @Binding var magnify: Bool
    @Binding var mode: OperatingMode
    @Binding var speaking: Bool
    var playSound: (() -> ())?

    var body: some View {
        HStack(alignment: .center) {
            maybeAlarmButton()
            maybeFontSizeButtons()
            Toggle(isOn: $speaking) {
                Text("Speak")
            }
            .frame(maxWidth: 105)
            Spacer()
            maybeFontSizeToggle()
            Button(action: { self.mode = .ask }) {
                stopButtonLabel()
            }
            .background(Color.accentColor)
            .cornerRadius(15)
        }
        .dynamicTypeSize(.large)
        .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
    }
    
    @ViewBuilder private func maybeAlarmButton() -> some View {
        if mode == .listen {
            EmptyView()
        } else {
            Button {
                playSound?()
            } label: {
                fontButtonImage(WhisperData.alertSound() + "-icon", pad: 5)
            }
            Spacer()
        }
    }

    private func fontButtonImage(_ name: String, pad: CGFloat = 0) -> some View {
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
            } label: {
                fontButtonImage("font-down-button")
            }
            .disabled(size == FontSizes.minTextSize)
            Button {
                self.size = FontSizes.nextTextLarger(self.size)
            } label: {
                fontButtonImage("font-up-button")
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

    static func modeB(_ i: Int) -> Binding<OperatingMode> {
        return Binding(
            get: { options[i].2 },
            set: { _ = $0 })
    }
    
    static var previews: some View {
        VStack {
            ForEach(0 ..< 10) {
                ControlView(size: sizeB($0), magnify: magnifyB($0), mode: modeB($0), speaking: magnifyB($0))
            }
        }
    }
}
