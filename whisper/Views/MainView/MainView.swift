// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI
import UIKit

let choiceButtonWidth = CGFloat(115)
let choiceButtonHeight = CGFloat(50)

let settingsUrl = URL(string: UIApplication.openSettingsURLString)!

struct MainView: View {    
    @StateObject private var model: MainViewModel = .init()
    @State var mode: OperatingMode = WhisperData.initialMode()
            
    var body: some View {
        if model.state == .unauthorized {
            Link("Enable Bluetooth to continue...", destination: settingsUrl)
        } else if model.state != .poweredOn {
            Text("Waiting for Bluetooth before continuing...")
        } else {
            switch mode {
            case .ask:
                ChoiceView(mode: $mode)
            case .listen:
                ListenView(mode: $mode)
            case .whisper:
                WhisperView(mode: $mode)
            }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
