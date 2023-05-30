// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI
import UIKit

let choiceButtonWidth = CGFloat(115)
let choiceButtonHeight = CGFloat(50)


struct MainView: View {
    @Environment(\.scenePhase) var scenePhase
    
    @State private var currentUserName: String = ""
    @State private var newUserName: String = ""
    @StateObject private var model: MainViewModel = .init()
    @State var mode: OperatingMode = WhisperData.initialMode()
            
    private var settingsUrl = URL(string: UIApplication.openSettingsURLString)!
    
    var body: some View {
        if model.state == .unauthorized {
            Link("Enable Bluetooth to continue...", destination: settingsUrl)
        } else if model.state != .poweredOn {
            Text("Waiting for Bluetooth before continuing...")
        } else {
            switch mode {
            case .ask:
                choiceView()
            case .listen:
                ListenView(mode: $mode)
            case .whisper:
                WhisperView(mode: $mode)
            }
        }
    }
    
    @ViewBuilder
    private func choiceView() -> some View {
        VStack(spacing: 60) {
            Form {
                Section(content: {
                    TextField("Your Name", text: $newUserName, prompt: Text("Dan"))
                        .onChange(of: newUserName) {
                            WhisperData.updateUserName($0)
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
        currentUserName = WhisperData.userName()
        newUserName = currentUserName
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
