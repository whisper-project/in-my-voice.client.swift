// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI
import SafariServices


struct ChoiceView: View {
    @Environment(\.scenePhase) var scenePhase

    @Binding var mode: OperatingMode
    @Binding var publisherUrl: TransportUrl

    @State private var currentUserName: String = ""
    @State private var newUserName: String = ""
    @State private var showWhisperButtons = false
    @State private var confirmWhisper = false
    @State private var confirmListen = false
    @State private var credentialsMissing = false
    @State private var lastSubscribedUrl: TransportUrl = PreferenceData.lastSubscriberUrl
    @FocusState private var nameEdit: Bool
    
    let nameWidth = CGFloat(350)
    let nameHeight = CGFloat(105)
    let choiceButtonWidth = CGFloat(140)
    let choiceButtonHeight = CGFloat(45)
    let website = "https://clickonetwo.github.io/whisper/"

    var body: some View {
        VStack(spacing: 40) {
            Form {
                Section(content: {
                    TextField("Your Name", text: $newUserName, prompt: Text("Fill in to continue…"))
                        .submitLabel(.done)
                        .onSubmit { 
                            newUserName = newUserName.trimmingCharacters(in: .whitespaces)
                            PreferenceData.updateUserName(newUserName)
                            currentUserName = newUserName
                            withAnimation {
                                self.showWhisperButtons = !currentUserName.isEmpty
                            }
                        }
                        .focused($nameEdit)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .allowsTightening(true)
                }, header: {
                    Text("Your Name")
                })
            }
            .frame(maxWidth: nameWidth, maxHeight: nameHeight)
            if (showWhisperButtons) {
                HStack(spacing: 30) {
                    Button(action: {
                        publisherUrl = ComboFactory.shared.publisherUrl
                        mode = .whisper
                    }) {
                        Text("Whisper")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .frame(width: choiceButtonWidth, height: choiceButtonHeight, alignment: .center)
                    }
                    .background(currentUserName == "" ? Color.gray : Color.accentColor)
                    .cornerRadius(15)
                    Button(action: {
                        publisherUrl = nil
                        mode = .listen
                    }) {
                        Text("Listen")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .frame(width: choiceButtonWidth, height: choiceButtonHeight, alignment: .center)
                    }
                    .background(Color.accentColor)
                    .cornerRadius(15)
                }
                .transition(.scale)
            }
            Button(action: {
                UIApplication.shared.open(settingsUrl)
            }) {
                Text("Settings")
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                    .frame(width: choiceButtonWidth, height: choiceButtonHeight, alignment: .center)
            }
            .background(Color.accentColor)
            .cornerRadius(15)
            VStack (spacing: 10) {
                Button(action: {
                    let vc = SFSafariViewController(url: URL(string: "\(website)instructions.html")!)
                    UIApplication.shared.firstKeyWindow?.rootViewController?.present(vc, animated: true)
                }) {
                    Text("How To Use")
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                        .frame(width: choiceButtonWidth, height: choiceButtonHeight, alignment: .center)
                }
                .background(Color.accentColor)
                .cornerRadius(15)
                HStack {
                    HStack {
                        Spacer()
                        Button("About", action: {
                            let vc = SFSafariViewController(url: URL(string: website)!)
                            UIApplication.shared.firstKeyWindow?.rootViewController?.present(vc, animated: true)
                        })
                    }.frame(width: choiceButtonWidth)
                    Spacer().frame(width: choiceButtonWidth/3)
                    HStack {
                        Button("Support", action: {
                            let vc = SFSafariViewController(url: URL(string: "\(website)support.html")!)
                            UIApplication.shared.firstKeyWindow?.rootViewController?.present(vc, animated: true)
                        })
                        Spacer()
                    }.frame(width: choiceButtonWidth)
                }
            }
        }
        .alert("First Launch", isPresented: $credentialsMissing) {
            Button("OK") { }
        } message: {
            Text("Sorry, but on its first launch after installation the app needs a few minutes to connect to the whisper server. Please try again.")
        }
        .onAppear { updateUserNameOnAppear() }
        .onChange(of: nameEdit) { isEditing in
            withAnimation {
                if isEditing {
                    showWhisperButtons = false
                } else {
                    showWhisperButtons = !currentUserName.isEmpty
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                logger.log("Reread user name going to choice view foreground")
                updateUserNameOnAppear()
            case .background, .inactive:
                break
            @unknown default:
                logger.error("Went to unknown phase: \(String(describing: newPhase))")
            }
        }
    }
    
    func updateUserNameOnAppear() {
        currentUserName = PreferenceData.userName()
        newUserName = currentUserName
        showWhisperButtons = !currentUserName.isEmpty
        nameEdit = currentUserName.isEmpty
    }
}

extension UIApplication {
    var firstKeyWindow: UIWindow? {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .first?.keyWindow
    }
}

struct ChoiceView_Previews: PreviewProvider {
    static let mode = Binding<OperatingMode>(get: { .ask }, set: { _ = $0 })
    static let publisherUrl = Binding<TransportUrl>(get: { nil }, set: { _ = $0 })

    static var previews: some View {
        ChoiceView(mode: mode, publisherUrl: publisherUrl)
    }
}
