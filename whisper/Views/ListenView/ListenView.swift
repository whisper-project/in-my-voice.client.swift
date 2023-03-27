// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct ListenView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    
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
                    .textSelection(.enabled)
                    .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                    .padding(10)
                    .frame(maxWidth: geometry.size.width,
                           maxHeight: geometry.size.height * pastTextProportion,
                           alignment: .bottomLeading)
                    .border(colorScheme == .light ? lightPastBorderColor : darkPastBorderColor, width: 2)
                    .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                Text(model.statusText)
                    .font(.caption)
                    .foregroundColor(colorScheme == .light ? lightLiveTextColor : darkLiveTextColor)
                Text(model.liveText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .textSelection(.enabled)
                    .foregroundColor(colorScheme == .light ? lightLiveTextColor : darkLiveTextColor)
                    .padding()
                    .frame(maxWidth: geometry.size.width,
                           maxHeight: geometry.size.height * liveTextProportion,
                           alignment: .topLeading)
                    .border(colorScheme == .light ? lightLiveBorderColor : darkLiveBorderColor, width: 2)
                    .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            }
        }
        .onAppear {
            print("Listener appeared")
            self.model.start()
        }
        .onDisappear {
            print("Listener disappeared")
            self.model.stop()
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                print("Went to background")
                model.wentToBackground()
            case .inactive:
                print("Went inactive")
            case .active:
                print("Went to foreground")
                model.wentToForeground()
            @unknown default:
                print("Went to unkown phase: \(newPhase)")
            }
        }
    }
}

struct ListenView_Previews: PreviewProvider {
    static let mode = Binding<OperatingMode>(get: { .listen }, set: { _ in print("Stop") })

    static var previews: some View {
        ListenView(mode: mode)
    }
}
