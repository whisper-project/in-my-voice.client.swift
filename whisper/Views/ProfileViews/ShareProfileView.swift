// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct ShareProfileView: View {
#if targetEnvironment(macCatalyst)
	@Environment(\.dismiss) private var dismiss
#endif

	@StateObject var profile: UserProfile = UserProfile.shared
	@State private var receivedId: String = ""
	@State private var receivedPassword: String = ""
	@State private var showStatus: Bool = false
	@State private var inProgress: Bool = false
	@State private var errorMessage: String = ""

    var body: some View {
		VStack {
			if profile.userPassword.isEmpty {
				StartSharingView()
			} else {
				StopSharingView()
			}
		}
		.onDisappear(perform: profile.update)
    }

	func StartSharingView() -> some View {
		Form {
			#if targetEnvironment(macCatalyst)
			HStack {
				Text("Profile Sharing is OFF")
					.font(.headline)
				Spacer()
				Button(action: { dismiss() }, label: { Text("Close") } )
			}
			#else
			Text("Profile Sharing is OFF")
				.font(.headline)
			#endif
			Section("Start profile sharing") {
				Text("To share your profile to another device, click here:")
				Button(action: { profile.startSharing() }) {
					Text("Start Sharing")
				}
			}
			Section("Receive a shared profile") {
				Text("To receive a profile from another device, first fill these fields:")
				TextField(text: $receivedId, label: { Text("Profile ID") })
					.autocorrectionDisabled()
					.textInputAutocapitalization(.never)
				TextField(text: $receivedPassword, label: { Text("Profile Secret") })
					.autocorrectionDisabled()
					.textInputAutocapitalization(.never)
				if (showStatus) {
					statusView()
				} else {
					Text("Once you've filled the fields, click this button:")
					Button(action: { receiveSharing() }, label: { Text("Receive Profile") })
						.disabled(receivedId.isEmpty || receivedPassword.isEmpty)
				}
			}
		}
	}

	func StopSharingView() -> some View {
		Form {
#if targetEnvironment(macCatalyst)
			HStack {
				Text("Profile Sharing is ON")
					.font(.headline)
				Spacer()
				Button(action: { dismiss() }, label: { Text("Close") } )
			}
#else
			Text("Profile Sharing is ON")
				.font(.headline)
#endif
			Section("Sharing your profile") {
				Text("To add your profile to a new device, copy these values to it:")
				HStack { 
					Text("Profile ID:").bold()
					Text("\(profile.id)").textSelection(.enabled)
					Button(action: { UIPasteboard.general.string = profile.id }, label: { Image(systemName: "square.on.square") })
				}
				.buttonStyle(.borderless)
				HStack {
					Text("Profile Secret:").bold()
					Text("\(profile.userPassword)").textSelection(.enabled)
					Button(action: { UIPasteboard.general.string = profile.userPassword }, label: { Image(systemName: "square.on.square") })
				}
				.buttonStyle(.borderless)
			}
			Section("Stop profile sharing") {
				Text("To disconnect this device and reset your profile, click this button:")
				Button(action: { profile.stopSharing() }) {
					Text("Stop Sharing")
				}
			}
		}
	}

	func receiveSharing() {
		self.showStatus = true
		self.inProgress = true
		profile.receiveSharing(id: receivedId,
							   password: receivedPassword,
							   completionHandler: { success, message in
			self.errorMessage = message
			self.inProgress = false
			self.showStatus = !success
		})
	}

	@ViewBuilder func statusView() -> some View {
		if inProgress {
			ProgressView(label: { Text("Fetching profile...") })
		} else {
			VStack(spacing: 5) {
				Text("Sharing Error").font(.headline)
				Text(errorMessage)
				Button(action: { showStatus = false }, label: { Text("OK") } )
			}
		}
	}
}

#Preview {
    ShareProfileView()
}
