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
        GeometryReader { proxy in
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
                TextField("", text: $model.pastText, axis: .vertical)
                    .onChange(of: model.pastText) { _ in
                        model.resetPastText()
                        focusField = false
                    }
                    .onSubmit {
                        focusField = false
                    }
                    .focused($focusField)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
                    .padding()
                    .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height * 3/4, alignment: .bottomLeading)
                    .border(.gray, width: 2)
                    .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                Text(model.statusText)
                    .font(.caption)
                Text(model.liveText)
                    .multilineTextAlignment(.leading)
                    .padding()
                    .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height * 1/4, alignment: .topLeading)
                    .border(.black, width: 2)
                    .padding(EdgeInsets(top: 10, leading: 20, bottom: 0, trailing: 20))
            }
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
