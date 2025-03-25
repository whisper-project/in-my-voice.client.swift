// Copyright 2025 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct SettingOption: Identifiable {
	var id: String
	var label: String
}

struct Setting: Identifiable {
	var id: String
	var name: String
	var options: [SettingOption]
	var initialValue: String
	var onChange: (String) -> Void
}

struct SettingsView: View {
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
    }
}

#Preview {
    SettingsView()
}
