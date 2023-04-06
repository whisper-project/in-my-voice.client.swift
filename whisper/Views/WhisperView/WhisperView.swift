// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct WhisperView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var mode: OperatingMode
    
    @State private var liveText: String = ""
    @FocusState private var focusField: String?
    @StateObject private var model: WhisperViewModel = .init()
    @State private var size = FontSizes.FontSize.normal

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 10) {
                HStack {
                    Spacer()
                    Button(action: { mode = .ask }) {
                        Text("Stop Whispering")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .padding(10)
                    }
                    .background(Color.accentColor)
                    .cornerRadius(15)
                    .padding(EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0))
                }
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 20))
                PastTextView(model: model.pastText)
                    .font(FontSizes.fontFor(size))
                    .textSelection(.enabled)
                    .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                    .padding()
                    .frame(maxWidth: proxy.size.width,
                           maxHeight: proxy.size.height * pastTextProportion,
                           alignment: .bottomLeading)
                    .border(colorScheme == .light ? lightPastBorderColor : darkPastBorderColor, width: 2)
                    .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                StatusTextView(size: $size, text: $model.statusText)
                TextEditor(text: $liveText)
                    .font(FontSizes.fontFor(size))
                    .onChange(of: liveText) { [liveText] new in
                        self.liveText = model.updateLiveText(old: liveText, new: new)
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
                    .padding()
                    .frame(maxWidth: proxy.size.width,
                           maxHeight: proxy.size.height * liveTextProportion,
                           alignment: .topLeading)
                    .border(colorScheme == .light ? lightLiveBorderColor : darkLiveBorderColor, width: 2)
                    .padding(EdgeInsets(top: 0, leading: 20, bottom: bottomViewPad + 5, trailing: 20))
            }
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
        }
        .onAppear {
            self.model.start()
            focusField = "liveText"
        }
        .onDisappear { self.model.stop() }
    }
}

struct WhisperView_Previews: PreviewProvider {
    static let mode = Binding<OperatingMode>(get: { .listen }, set: { _ in print("Stop") })

    static var previews: some View {
        WhisperView(mode: mode)
    }
}
