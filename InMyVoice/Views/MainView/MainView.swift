// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct MainView: View {
    @Environment(\.colorScheme) private var colorScheme
	@Environment(\.dynamicTypeSize) private var dynamicTypeSize

	@AppStorage("main_view_large_sizes_setting") private var useLargeSizes: Bool = false

	@State var mode: OperatingMode = .ask
    @StateObject private var model: MainViewModel = .init()
            
    var body: some View {
        switch mode {
        case .ask:
            VStack {
                Spacer()
                ChoiceView(mode: $mode, TcpStatus: $model.status)
					.onAppear {
						UserProfile.shared.update()
					}
                Spacer()
				Toggle("Larger Type", isOn: $useLargeSizes)
					.frame(maxWidth: useLargeSizes ? 220 : 175)
                Text("v\(versionString)")
                    .textSelection(.enabled)
                    .font(FontSizes.fontFor(name: .xxxsmall))
                    .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                    .padding(EdgeInsets(top: 20, leading: 0, bottom: 5, trailing: 0))
            }
			.dynamicTypeSize(useLargeSizes ? .accessibility1 : dynamicTypeSize)
        case .whisper:
			WhisperView(mode: $mode)
        }
    }
}
