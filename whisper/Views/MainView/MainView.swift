// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct MainView: View {
    @State private var mode: OperatingMode = MainViewModel.get_initial_mode()
    @StateObject private var model: MainViewModel = .init()
    
    var body: some View {
        if model.state != .poweredOn {
            Text("Enable Bluetooth to start scanning")
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
        VStack {
            HStack(spacing: 60) {
                Button(action: { self.mode = .whisper }) {
                    Text("Whisper")
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                        .padding(10)
                }
                .background(Color.blue)
                .cornerRadius(15)
                Button(action: { self.mode = .listen }) {
                    Text("Listen")
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                        .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                }
                .background(Color.blue)
                .cornerRadius(15)
            }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
