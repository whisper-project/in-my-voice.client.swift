// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI
import SafariServices


struct ChoiceView: View {
    @Environment(\.scenePhase) var scenePhase
    
    @Binding var mode: OperatingMode

    @State private var currentUserName: String = ""
    @State private var newUserName: String = ""
    
    var body: some View {
        VStack(spacing: 60) {
            Form {
                Section(content: {
                    TextField("Your Name", text: $newUserName, prompt: Text("Dan"))
                        .onChange(of: newUserName) {
                            PreferenceData.updateUserName($0)
                            self.currentUserName = $0
                        }
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .allowsTightening(true)
                        .truncationMode(.head)
                }, header: {
                    Text("Your Name")
                })
            }
            .frame(maxWidth: 300, maxHeight: 105)
            HStack(spacing: 60) {
                VStack(spacing: 60) {
                    Button(action: {
                        mode = .whisper
                    }) {
                        Text("Whisper")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .frame(width: choiceButtonWidth, height: choiceButtonHeight, alignment: .center)
                    }
                    .background(currentUserName == "" ? Color.gray : Color.accentColor)
                    .cornerRadius(15)
                    .disabled(currentUserName == "")
                }
                VStack(spacing: 60) {
                    Button(action: {
                        mode = .listen
                    }) {
                        Text("Listen")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .frame(width: choiceButtonWidth, height: choiceButtonHeight, alignment: .center)
                    }
                    .background(Color.accentColor)
                    .cornerRadius(15)
                    .disabled(currentUserName == "")
                }
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
            Button(action: {
                let vc = SFSafariViewController(url: URL(string: "https://clickonetwo.github.io/whisper/")!)
                UIApplication.shared.firstKeyWindow?.rootViewController?.present(vc, animated: true)
            }) {
                Text("About")
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                    .frame(width: choiceButtonWidth, height: choiceButtonHeight, alignment: .center)
            }
            .background(Color.accentColor)
            .cornerRadius(15)
        }
        .onAppear { updateUserName() }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                logger.log("Reread preferences going to choice view foreground")
                updateUserName()
            case .background, .inactive:
                break
            @unknown default:
                logger.error("Went to unknown phase: \(String(describing: newPhase))")
            }
        }
    }
    
    func updateUserName() {
        currentUserName = PreferenceData.userName()
        newUserName = currentUserName
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
    static let mode = Binding<OperatingMode>(get: { .listen }, set: { _ = $0 })

    static var previews: some View {
        ChoiceView(mode: mode)
    }
}
