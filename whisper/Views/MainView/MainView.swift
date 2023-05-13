// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct MainView: View {
    @State private var currentDeviceName: String = WhisperData.deviceName
    @State private var newDeviceName: String = WhisperData.deviceName
    @StateObject private var model: MainViewModel = .init()
    @State var mode: OperatingMode = {
        let defaults = UserDefaults.standard
        let val = defaults.integer(forKey: modePreferenceKey)
        return OperatingMode(rawValue: val) ?? .ask
    }()
    @State var speaking: Bool = false
            
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
                ListenView(mode: $mode, initialSpeaking: speaking)
            case .whisper:
                WhisperView(mode: $mode, initialSpeaking: speaking)
            }
        }
    }
    
    @ViewBuilder
    private func choiceView() -> some View {
        VStack(spacing: 60) {
            Form {
                Section(content: {
                    TextField("Your Name", text: $newDeviceName, prompt: Text("Dan"))
                        .onChange(of: newDeviceName) {
                            WhisperData.updateDeviceName($0)
                            self.currentDeviceName = $0
                        }
                        .textInputAutocapitalization(TextInputAutocapitalization.never)
                        .disableAutocorrection(true)
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
                        speaking = false
                    }) {
                        Text("Whisper")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .padding(10)
                    }
                    .background(WhisperData.deviceName == "" ? Color.gray : Color.accentColor)
                    .cornerRadius(15)
                    .disabled(currentDeviceName == "")
                    Button(action: {
                        mode = .whisper
                        speaking = true
                    }) {
                        Text("Speak")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .padding(10)
                    }
                    .background(WhisperData.deviceName == "" ? Color.gray : Color.accentColor)
                    .cornerRadius(15)
                    .disabled(currentDeviceName == "")
                }
                VStack(spacing: 60) {
                    Button(action: {
                        mode = .listen
                        speaking = false
                    }) {
                        Text("Listen")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .padding(10)
                    }
                    .background(Color.accentColor)
                    .cornerRadius(15)
                    .disabled(currentDeviceName == "")
                    Button(action: {
                        mode = .listen
                        speaking = true
                    }) {
                        Text("Hear")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .padding(10)
                    }
                    .background(Color.accentColor)
                    .cornerRadius(15)
                    .disabled(currentDeviceName == "")
                }
            }
            Button(action: {
                UIApplication.shared.open(settingsUrl)
            }) {
                Text("Settings")
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                    .padding(10)
            }
            .background(Color.accentColor)
            .cornerRadius(15)
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
