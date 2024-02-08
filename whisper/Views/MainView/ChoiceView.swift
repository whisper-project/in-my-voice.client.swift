// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI
import SafariServices


struct ChoiceView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    @Binding var mode: OperatingMode
    @Binding var publisherUrl: TransportUrl
    @Binding var transportStatus: TransportStatus

    @State private var currentUserName: String = ""
    @State private var newUserName: String = ""
    @State private var showWhisperButtons = false
    @State private var credentialsMissing = false
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
                if transportStatus != .on {
                    switch transportStatus {
                    case .off:
                        Link("Enable Bluetooth or Wireless to whisper or listen...", destination: settingsUrl)
                            .font(FontSizes.fontFor(name: .normal))
                            .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                    case .disabled:
                        Link("Enable Bluetooth to listen...", destination: settingsUrl)
                            .font(FontSizes.fontFor(name: .normal))
                            .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                    case .waiting:
                        Text("Waiting for Bluetooth to listen...")
                            .font(FontSizes.fontFor(name: .normal))
                            .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                    case .on:
                        fatalError("Can't happen")
                    }
                }
                HStack(spacing: 30) {
                    Button(action: {
                        publisherUrl = ComboFactory.shared.publisherForm(PreferenceData.personalPublisherUrl)
                        mode = .whisper
                    }) {
                        Text("Whisper")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .frame(width: choiceButtonWidth, height: choiceButtonHeight, alignment: .center)
                    }
                    .background(currentUserName == "" ? Color.gray : Color.accentColor)
                    .cornerRadius(15)
                    .disabled(transportStatus == .off)
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
                    .disabled(transportStatus != .on)
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
        .onChange(of: nameEdit) {
            withAnimation {
                if nameEdit {
                    showWhisperButtons = false
                } else {
                    showWhisperButtons = !currentUserName.isEmpty
                }
            }
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                logger.log("Reread user name going to choice view foreground")
                updateUserNameOnAppear()
            case .background, .inactive:
                break
            @unknown default:
                logger.error("Went to unknown phase: \(String(describing: scenePhase))")
            }
        }
    }
    
    func updateUserNameOnAppear() {
        currentUserName = PreferenceData.userName()
        newUserName = currentUserName
        showWhisperButtons = !currentUserName.isEmpty
        nameEdit = currentUserName.isEmpty
    }
    
    func canListen() -> Bool {
        if case .on = transportStatus {
            return true
        } else {
            return false
        }
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
    static let transportStatus = Binding<TransportStatus>( get: { .on }, set: { _ = $0 })

    static var previews: some View {
        ChoiceView(mode: mode, publisherUrl: publisherUrl, transportStatus: transportStatus)
    }
}
