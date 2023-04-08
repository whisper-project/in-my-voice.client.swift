// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct MainView: View {
    @State private var currentDeviceName: String = WhisperData.deviceName
    @State private var newDeviceName: String = WhisperData.deviceName
    @StateObject private var model: MainViewModel = .init()
    
    private var settingsUrl = UIApplication.openSettingsURLString
        
    var body: some View {
        if model.state == .unauthorized {
            Link("Enable Bluetooth to continue...", destination: URL(string: settingsUrl)!)
        } else if model.state != .poweredOn {
            Text("Waiting for Bluetooth before continuing...")
        } else {
            switch model.mode {
            case .ask:
                choiceView()
            case .listen:
                ListenView(exitAction: model.choiceMode)
            case .whisper:
                WhisperView(exitAction: model.choiceMode)
            }
        }
    }
    
    @ViewBuilder
    private func choiceView() -> some View {
        VStack(spacing: 60) {
            Form {
                Section(content: {
                    TextField("Whisperer Name", text: $newDeviceName, prompt: Text("Required for whispering"))
                        .onSubmit {
                            WhisperData.updateDeviceName(self.newDeviceName)
                            self.currentDeviceName = WhisperData.deviceName
                        }
                        .textInputAutocapitalization(TextInputAutocapitalization.never)
                        .disableAutocorrection(true)
                }, header: {
                    Text("Whisperer Name")
                })
            }
            .frame(maxWidth: 300, maxHeight: 105)
            HStack(spacing: 60) {
                VStack(spacing: 60) {
                    Button(action: { self.model.setMode(.whisper) }) {
                        Text("Whisper")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .padding(10)
                    }
                    .background(WhisperData.deviceName == "" ? Color.gray : Color.accentColor)
                    .cornerRadius(15)
                    .disabled(currentDeviceName == "")
                    Button(action: { self.model.setMode(.whisper, always: true) }) {
                        Text("Always\nWhisper")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .padding(10)
                    }
                    .background(WhisperData.deviceName == "" ? Color.gray : Color.accentColor)
                    .cornerRadius(15)
                    .disabled(currentDeviceName == "")
                }
                VStack(spacing: 60) {
                    Button(action: { self.model.setMode(.listen) }) {
                        Text("Listen")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .padding(EdgeInsets(top: 10, leading: 25, bottom: 10, trailing: 25))
                    }
                    .background(Color.accentColor)
                    .cornerRadius(15)
                    Button(action: { self.model.setMode(.listen, always: true) }) {
                        Text("Always\nListen")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                    }
                    .background(Color.accentColor)
                    .cornerRadius(15)
                }
            }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
