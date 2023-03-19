// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct WhisperView: View {
    @Binding var mode: OperatingMode
    @State private var liveText: String = ""
    @StateObject private var model: WhisperViewModel = .init()

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
                Text(model.pastText)
                    .foregroundColor(.gray)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .padding()
                    .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height * 3/4, alignment: .bottomLeading)
                    .border(.gray, width: 2)
                    .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                Text(model.statusText)
                    .font(.caption)
                TextField("", text: $liveText)
                    .onChange(of: liveText) { [liveText] new in
                        if model.updateLiveText(old: liveText, new: new) {
                            self.liveText = ""
                        }
                    }
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .padding()
                    .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height * 1/4, alignment: .topLeading)
                    .border(.black, width: 2)
                    .padding(EdgeInsets(top: 0, leading: 20, bottom: 10, trailing: 20))
            }
        }
        .onAppear { self.model.start() }
        .onDisappear { self.model.stop() }
    }
}

struct WhisperView_Previews: PreviewProvider {
    static let mode = Binding<OperatingMode>(get: { .listen }, set: { _ in print("Stop") })

    static var previews: some View {
        WhisperView(mode: mode)
    }
}
