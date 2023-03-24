// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct ListenView: View {
    @Binding var mode: OperatingMode
    @FocusState var focusField: Bool
    @StateObject private var model: ListenViewModel = .init()

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                HStack {
                    Spacer()
                    Button(action: { mode = .ask }) {
                        Text("Stop Listening")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .padding(10)
                    }
                    .background(Color.accentColor)
                    .cornerRadius(15)
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 20))
                }
                PastTextView(model: model.pastText)
                    .padding(10)
                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height * 3 / 4, alignment: .bottomLeading)
                    .border(.gray, width: 2)
                    .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                Text(model.statusText)
                    .font(.caption)
                Text(model.liveText)
                    .padding()
                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height * 1/4, alignment: .topLeading)
                    .border(.black, width: 2)
                    .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            }
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
        }
        .onAppear { self.model.start() }
        .onDisappear { self.model.stop() }
    }
}

struct ListenView_Previews: PreviewProvider {
    static let mode = Binding<OperatingMode>(get: { .listen }, set: { _ in print("Stop") })

    static var previews: some View {
        ListenView(mode: mode)
    }
}
