// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct ListenView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    @Binding var mode: OperatingMode
    
    @FocusState var focusField: Bool
    @StateObject private var model: ListenViewModel = .init()
    @State private var size = FontSizes.FontName.normal.rawValue
    @State private var magnify: Bool = false
    @State private var showStatusDetail: Bool = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                ControlView(size: $size, magnify: $magnify, mode: $mode)
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
                    .dynamicTypeSize(magnify ? .accessibility3 : dynamicTypeSize)
                StatusTextView(text: $model.statusText)
                    .onTapGesture {
                        showStatusDetail = true
                    }
                    .popover(isPresented: $showStatusDetail) {
                        WhisperersView(model: model)
                    }
                Text(model.liveText)
                    .font(FontSizes.fontFor(size))
                    .truncationMode(.head)
                    .textSelection(.enabled)
                    .foregroundColor(colorScheme == .light ? lightLiveTextColor : darkLiveTextColor)
                    .padding()
                    .frame(maxWidth: geometry.size.width,
                           maxHeight: geometry.size.height * liveTextProportion,
                           alignment: .topLeading)
                    .border(colorScheme == .light ? lightLiveBorderColor : darkLiveBorderColor, width: 2)
                    .padding(EdgeInsets(top: 0, leading: 20, bottom: listenViewBottomPad, trailing: 20))
                    .dynamicTypeSize(magnify ? .accessibility3 : dynamicTypeSize)
            }
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
        }
        .alert("Lost Connection", isPresented: $model.wasDropped) {
            Button("OK") { mode = .ask }
        } message: {
            Text("The connection to the listener was lost")
        }
        .alert("No Whisperers", isPresented: $model.timedOut) {
            Button("OK") { mode = .ask }
        } message: {
            Text("Couldn't find a whisperer.  Try again when a whisperer is ready.")
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
        ListenView(mode: mode)
    }
}
