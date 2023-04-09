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
    
    var body: some View {
        HStack (alignment: .center) {
            Button {
                self.size = FontSizes.nextTextSmaller(self.size)
            } label: {
                imageInvertInDarkMode("font-down-button")
                    .frame(width: 50, height: 50)
                    .border(colorScheme == .light ? .black : .white, width: 1)
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: fontButtonPad))
            }
            .disabled(size == FontSizes.minTextSize)
            Button {
                self.size = FontSizes.nextTextLarger(self.size)
            } label: {
                imageInvertInDarkMode("font-up-button")
                    .frame(width: 50, height: 50)
                    .border(colorScheme == .light ? .black : .white, width: 1)
            }
            Spacer()
            .disabled(size == FontSizes.maxTextSize)
            Toggle(isOn: $magnify) {
                Text("Large Sizes")
            }
            .frame(maxWidth: 110)
            Spacer()
            Button(action: { self.mode = .ask }) {
                Text(computeButtonText())
                    .foregroundColor(.white)
                    .font(.body)
                    .fontWeight(.bold)
                    .padding(10)
            }
            .background(Color.accentColor)
            .cornerRadius(15)
        }
        .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
    }
    
    @ViewBuilder func imageInvertInDarkMode(_ name: String) -> some View {
        if colorScheme == .dark {
            Image(name).resizable().colorInvert()
        } else {
            Image(name).resizable()
        }
    }
    
    private func computeButtonText() -> String {
        return mode == .listen ? "Stop Listening" : "Stop Whispering"
    }
    
    private func sliderRange() -> ClosedRange<Float> {
        return Float(FontSizes.minTextSize)...Float(FontSizes.maxTextSize)
    }
}

struct ControlView_Previews: PreviewProvider {
    static var size: Binding<Int> = Binding(get: { return FontSizes.minTextSize }, set: { _ = $0 })
    static var magnify: Binding<Bool> = Binding(get: { return false }, set: { _ = $0 })
    static var mode: Binding<OperatingMode> = Binding(get: { return .listen }, set: { _ = $0 })

    static var previews: some View {
        ControlView(size: size, magnify: magnify, mode: mode)
    }
}
