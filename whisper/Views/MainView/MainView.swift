// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI
import UIKit

let settingsUrl = URL(string: UIApplication.openSettingsURLString)!

struct MainView: View {
    @Binding var mode: OperatingMode
    @Binding var publisherUrl: TransportUrl
    
    @StateObject private var model: MainViewModel = .init()
            
    var body: some View {
        if case TransportStatus.disabled(let message) = model.status {
            Link(message, destination: settingsUrl)
        } else if case TransportStatus.off(let message) = model.status {
            Text(message)
        } else {
            switch mode {
            case .ask:
                ChoiceView(mode: $mode, publisherUrl: $publisherUrl)
            case .listen:
                ListenView(mode: $mode, publisherUrl: publisherUrl)
            case .whisper:
                WhisperView(mode: $mode, publisherUrl: publisherUrl)
            }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static let mode = Binding<OperatingMode>(get: { .ask }, set: { _ = $0 })
    static let publisherUrl = Binding<TransportUrl>(get: { nil }, set: { _ = $0 })

    static var previews: some View {
        MainView(mode: mode, publisherUrl: publisherUrl)
    }
}
