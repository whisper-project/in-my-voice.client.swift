// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct WhisperView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.scenePhase) var scenePhase

    @Binding var mode: OperatingMode
    var publisherUrl: TransportUrl

    @State private var liveText: String = ""
    @FocusState private var focusField: String?
    @StateObject private var model: WhisperViewModel
    @State private var size = FontSizes.FontName.normal.rawValue
    @State private var magnify: Bool = false
    @State private var showStatusDetail: Bool = false
    
    init(mode: Binding<OperatingMode>, publisherUrl: TransportUrl) {
        self._mode = mode
        self.publisherUrl = publisherUrl
        self._model = StateObject(wrappedValue: WhisperViewModel(publisherUrl))
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 10) {
                ControlView(size: $size, magnify: $magnify, mode: $mode, speaking: $model.speaking, playSound: model.playSound)
                    .padding(EdgeInsets(top: whisperViewTopPad, leading: sidePad, bottom: 0, trailing: sidePad))
                PastTextView(mode: .whisper, model: model.pastText)
                    .font(FontSizes.fontFor(size))
                    .textSelection(.enabled)
                    .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                    .padding(innerPad)
                    .frame(maxWidth: proxy.size.width,
                           maxHeight: proxy.size.height * pastTextProportion,
                           alignment: .bottomLeading)
                    .border(colorScheme == .light ? lightPastBorderColor : darkPastBorderColor, width: 2)
                    .padding(EdgeInsets(top: 0, leading: sidePad, bottom: 0, trailing: sidePad))
                    .dynamicTypeSize(magnify ? .accessibility3 : dynamicTypeSize)
                StatusTextView(text: $model.statusText, publisherUrl: publisherUrl)
                    .onTapGesture {
                        self.showStatusDetail = true
                    }
                    .popover(isPresented: $showStatusDetail) {
                        ListenersView(model: model)
                    }
                TextEditor(text: $liveText)
                    .font(FontSizes.fontFor(size))
                    .truncationMode(.head)
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
                    .padding(innerPad)
                    .frame(maxWidth: proxy.size.width,
                           maxHeight: proxy.size.height * liveTextProportion,
                           alignment: .topLeading)
                    .border(colorScheme == .light ? lightLiveBorderColor : darkLiveBorderColor, width: 2)
                    .padding(EdgeInsets(top: 0, leading: sidePad, bottom: whisperViewBottomPad, trailing: sidePad))
                    .dynamicTypeSize(magnify ? .accessibility3 : dynamicTypeSize)
            }
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
        }
        .alert("Connection Failure", isPresented: $model.connectionError) {
            Button("OK") { mode = .ask }
        } message: {
            Text("Unable to establish a connection.\n(Detailed error: \(self.model.connectionErrorDescription))")
        }
        .onAppear {
            logger.log("WhisperView appeared")
            self.model.start()
            focusField = "liveText"
        }
        .onDisappear {
            logger.log("WhisperView disappeared")
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

struct WhisperView_Previews: PreviewProvider {
    static var mode: Binding<OperatingMode> = Binding(get: { .whisper }, set: { _ = $0 })

    static var previews: some View {
        WhisperView(mode: mode, publisherUrl: nil)
    }
}
