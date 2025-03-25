// Copyright 2025 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct SettingView: View {
	@State var chosenSetting: String
	var setting: Setting

	init(_ setting: Setting) {
		self.setting = setting
		self.chosenSetting = setting.initialValue
	}

    var body: some View {
		Picker(setting.name, selection: $chosenSetting) {
			ForEach(setting.options) { option in
				Text(option.label)
			}
		}
		.onChange(of: chosenSetting) {
			setting.onChange(chosenSetting)
		}
    }
}

#Preview {
    SettingView(
		Setting(
			id: "test",
			name: "Test",
			options: [
				SettingOption(id: "first", label: "First"),
				SettingOption(id: "second", label: "Second"),
			],
			initialValue: "second",
			onChange: {val in print("Changed to: \(val)")}
		)
	)
}
