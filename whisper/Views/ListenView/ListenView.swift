// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct ListenView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    
    var exitAction: () -> ()
    
    @FocusState var focusField: Bool
    @StateObject private var model: ListenViewModel = .init()
    @State private var size = FontSizes.FontSize.normal
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                HStack {
                    Spacer()
                    Button(action: exitAction) {
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
                    .font(FontSizes.fontFor(size))
                    .textSelection(.enabled)
                    .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                    .padding(10)
                    .frame(maxWidth: geometry.size.width,
                           maxHeight: geometry.size.height * pastTextProportion,
                           alignment: .bottomLeading)
                    .border(colorScheme == .light ? lightPastBorderColor : darkPastBorderColor, width: 2)
                    .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                StatusTextView(size: $size, text: $model.statusText)
                Text(model.liveText)
                    .font(FontSizes.fontFor(size))
                    .textSelection(.enabled)
                    .foregroundColor(colorScheme == .light ? lightLiveTextColor : darkLiveTextColor)
                    .padding()
                    .frame(maxWidth: geometry.size.width,
                           maxHeight: geometry.size.height * liveTextProportion,
                           alignment: .topLeading)
                    .border(colorScheme == .light ? lightLiveBorderColor : darkLiveBorderColor, width: 2)
                    .padding(EdgeInsets(top: 0, leading: 20, bottom: listenViewBottomPad, trailing: 20))
            }
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
        }
        .onAppear {
            logger.log("ListenView appeared")
            self.model.start()
        }
        .onDisappear {
            logger.log("ListenView disappeared")
            self.model.stop()
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                logger.log("Went to background")
                model.wentToBackground()
            case .inactive:
                logger.log("Went inactive")
            case .active:
                logger.log("Went to foreground")
                model.wentToForeground()
            @unknown default:
                logger.error("Went to unknown phase: \(String(describing: newPhase))")
            }
        }
    }
}

struct ListenView_Previews: PreviewProvider {
    static let mode = Binding<OperatingMode>(get: { .listen }, set: { _ = $0 })

    static var previews: some View {
        ListenView(exitAction: {})
    }
}
