// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct ListenView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.scenePhase) var scenePhase

    @Binding var mode: OperatingMode
	@Binding var restart: Bool
    var conversation: ListenConversation?

    @FocusState var focusField: Bool
    @StateObject private var model: ListenViewModel
	@State private var size = PreferenceData.sizeWhenListening
	@State private var magnify: Bool = PreferenceData.magnifyWhenListening
	@State private var confirmStop: Bool = false

    // set this once at view creation
    private var listenerLiveTextOnTop = !PreferenceData.listenerMatchesWhisperer()
    
	init(mode: Binding<OperatingMode>, restart: Binding<Bool>, conversation: ListenConversation?) {
        self._mode = mode
		self._restart = restart
		self.conversation = conversation
		self._model = StateObject(wrappedValue: ListenViewModel(conversation))
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
				ControlView(size: $size, magnify: $magnify, mode: mode, maybeStop: maybeStop)
                    .padding(EdgeInsets(top: listenViewTopPad, leading: sidePad, bottom: 0, trailing: sidePad))
                if (listenerLiveTextOnTop) {
                    Text(model.liveText)
                        .font(FontSizes.fontFor(size))
                        .truncationMode(.head)
                        .textSelection(.enabled)
                        .foregroundColor(colorScheme == .light ? lightLiveTextColor : darkLiveTextColor)
                        .padding(innerPad)
                        .frame(maxWidth: geometry.size.width,
                               maxHeight: geometry.size.height * liveTextProportion,
                               alignment: .topLeading)
                        .border(colorScheme == .light ? lightLiveBorderColor : darkLiveBorderColor, width: 2)
                        .padding(EdgeInsets(top: 0, leading: sidePad, bottom: 0, trailing: sidePad))
                        .dynamicTypeSize(magnify ? .accessibility3 : dynamicTypeSize)
                } else {
                    PastTextView(mode: .listen, model: model.pastText)
                        .font(FontSizes.fontFor(size))
                        .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                        .padding(innerPad)
                        .frame(maxWidth: geometry.size.width,
                               maxHeight: geometry.size.height * pastTextProportion,
                               alignment: .bottomLeading)
                        .border(colorScheme == .light ? lightPastBorderColor : darkPastBorderColor, width: 2)
                        .padding(EdgeInsets(top: 0, leading: sidePad, bottom: 0, trailing: sidePad))
                        .dynamicTypeSize(magnify ? .accessibility3 : dynamicTypeSize)
                        .textSelection(.enabled)
                }
                StatusTextView(text: $model.statusText, mode: .listen, conversation: nil)
                    .onTapGesture {
                        model.showStatusDetail = true
                    }
                    .popover(isPresented: $model.showStatusDetail) {
                        WhisperersView(model: model)
                    }
                if (!listenerLiveTextOnTop) {
                    Text(model.liveText)
                        .font(FontSizes.fontFor(size))
                        .truncationMode(.head)
                        .textSelection(.enabled)
                        .foregroundColor(colorScheme == .light ? lightLiveTextColor : darkLiveTextColor)
                        .padding(innerPad)
                        .frame(maxWidth: geometry.size.width,
                               maxHeight: geometry.size.height * liveTextProportion,
                               alignment: .topLeading)
                        .border(colorScheme == .light ? lightLiveBorderColor : darkLiveBorderColor, width: 2)
                        .padding(EdgeInsets(top: 0, leading: sidePad, bottom: listenViewBottomPad, trailing: sidePad))
                        .dynamicTypeSize(magnify ? .accessibility3 : dynamicTypeSize)
                } else {
                    PastTextView(mode: .listen, model: model.pastText)
                        .font(FontSizes.fontFor(size))
                        .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                        .padding(innerPad)
                        .frame(maxWidth: geometry.size.width,
                               maxHeight: geometry.size.height * pastTextProportion,
                               alignment: .bottomLeading)
                        .border(colorScheme == .light ? lightPastBorderColor : darkPastBorderColor, width: 2)
                        .padding(EdgeInsets(top: 0, leading: sidePad, bottom: listenViewBottomPad, trailing: sidePad))
                        .dynamicTypeSize(magnify ? .accessibility3 : dynamicTypeSize)
                        .textSelection(.enabled)
                }
            }
        }
		.multilineTextAlignment(.leading)
		.lineLimit(nil)
		.alert("Confirm Stop", isPresented: $confirmStop) {
			Button("Stop") {
				model.stop()
				mode = .ask
			}
			Button("Don't Stop") {
			}
		} message: {
			Text("Do you really want to stop \(mode == .whisper ? "whispering" : "listening")?")
		}
        .alert("Connection Failure", isPresented: $model.connectionError) {
            Button("OK") { mode = .ask }
        } message: {
            Text("Lost connection to Whisperer: \(self.model.connectionErrorDescription)")
        }
        .alert("Conversation Ended", isPresented: $model.conversationEnded) {
            Button("OK") { mode = .ask }
        } message: {
            Text("The Whisperer has ended the conversation")
        }
        .onAppear {
            logger.log("ListenView appeared")
            self.model.start()
        }
        .onDisappear {
            logger.log("ListenView disappeared")
            self.model.stop()
        }
		.onChange(of: model.conversationRestarted) {
			restart = true
			mode = .ask
		}
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .background:
                logger.log("Went to background")
                model.wentToBackground()
            case .inactive:
                logger.log("Went inactive")
            case .active:
                logger.log("Went to foreground")
                model.wentToForeground()
            @unknown default:
                logger.error("Went to unknown phase: \(String(describing: scenePhase), privacy: .public)")
            }
        }
    }

	private func maybeStop() {
		confirmStop = true
	}
}

struct ListenView_Previews: PreviewProvider {
	static let mode: Binding<OperatingMode> = makeBinding(.listen)
	static let restart: Binding<Bool> = makeBinding(false)

    static var previews: some View {
		ListenView(mode: mode, restart: restart, conversation: nil)
    }
}
