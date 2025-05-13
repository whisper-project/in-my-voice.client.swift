// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct MainView: View {
    @Environment(\.colorScheme) private var colorScheme
	@Environment(\.dynamicTypeSize) private var dynamicTypeSize

	@State var mode: OperatingMode = .ask
	@State var magnify: Bool = PreferenceData.useLargeFontSizes
    @StateObject private var model: MainViewModel = .init()

    var body: some View {
        switch mode {
        case .ask:
            VStack {
                Spacer()
				ChoiceView(mode: $mode, magnify: $magnify)
                Spacer()
				if (platformInfo != "mac") {
					Toggle("Larger Type", isOn: $magnify)
						.frame(maxWidth: magnify ? 250 : 200)
						.onChange(of: magnify) {
							PreferenceData.useLargeFontSizes = magnify
						}
				}
                Text("v\(versionString)")
                    .textSelection(.enabled)
                    .font(FontSizes.fontFor(name: .xxxsmall))
                    .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                    .padding(EdgeInsets(top: 20, leading: 0, bottom: 5, trailing: 0))
            }
			.alert("Notification", isPresented: $model.showMessage) {
				Text(LocalizedStringKey(model.message))
				Button("OK") {
					self.model.showMessage = false
				}
			}
			.dynamicTypeSize(magnify ? .accessibility1 : dynamicTypeSize)
        case .whisper:
			WhisperView(mode: $mode, magnify: $magnify)
				.alert("Notification", isPresented: $model.showMessage) {
					Text(LocalizedStringKey(model.message))
					Button("OK") {
						self.model.showMessage = false
					}
				}
        }
    }
}
