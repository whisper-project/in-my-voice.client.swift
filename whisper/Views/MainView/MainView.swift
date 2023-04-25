// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct MainView: View {
    @State private var currentDeviceName: String = WhisperData.deviceName
    @State private var newDeviceName: String = WhisperData.deviceName
    @StateObject private var model: MainViewModel = .init()
            
    var body: some View {
        switch model.mode {
        case .ask:
            choiceView()
        case .listen:
            ListenView(mode: $model.mode)
        case .whisper:
            WhisperView(mode: $model.mode)
        }
    }
    
    @ViewBuilder
    private func choiceView() -> some View {
        VStack(spacing: 60) {
            Form {
                Section(content: {
                    TextField("Your Name & Device", text: $newDeviceName, prompt: Text("Dan on iPhone"))
                        .onChange(of: newDeviceName) {
                            WhisperData.updateDeviceName($0)
                            self.currentDeviceName = $0
                        }
                        .textInputAutocapitalization(TextInputAutocapitalization.never)
                        .disableAutocorrection(true)
                        .truncationMode(.head)
                }, header: {
                    Text("Your Name & Device")
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
                    .disabled(currentDeviceName == "")
                    Button(action: { self.model.setMode(.listen, always: true) }) {
                        Text("Always\nListen")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                    }
                    .background(Color.accentColor)
                    .cornerRadius(15)
                    .disabled(currentDeviceName == "")
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
