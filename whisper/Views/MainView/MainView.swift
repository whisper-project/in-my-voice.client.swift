// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI
import UIKit

let settingsUrl = URL(string: UIApplication.openSettingsURLString)!

struct MainView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var mode: OperatingMode
    @Binding var publisherUrl: TransportUrl
    
    @StateObject private var model: MainViewModel = .init()
            
    var body: some View {
        switch mode {
        case .ask:
            VStack {
                Spacer()
                ChoiceView(mode: $mode, publisherUrl: $publisherUrl, transportStatus: $model.status)
                Spacer()
                Text("v\(versionString)")
                    .textSelection(.enabled)
                    .font(FontSizes.fontFor(name: .xxxsmall))
                    .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                    .padding(EdgeInsets(top: 20, leading: 0, bottom: 5, trailing: 0))
            }
        case .listen:
            ListenView(mode: $mode, publisherUrl: publisherUrl)
        case .whisper:
            WhisperView(mode: $mode, publisherUrl: publisherUrl)
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
