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
	@State private var success: Bool = true
	@State private var message: String = "The profile was received"

    var body: some View {
		VStack {
			if profile.userPassword.isEmpty {
				StartSharingView()
			} else {
				StopSharingView()
			}
		}
		.alert("Sharing Status", isPresented: $showStatus, actions: { }, message: { Text(self.message) })
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
				TextField(text: $receivedPassword, label: { Text("Password") })
				Text("Once you've filled the fields, click this button:")
				Button(action: { receiveSharing() }, label: { Text("Receive Profile") })
					.disabled(receivedId.isEmpty || receivedPassword.isEmpty)
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
					ShareLink(item: profile.id, label: { Image(systemName: "square.on.square") })
				}
				.buttonStyle(.borderless)
				HStack {
					Text("Password:").bold()
					Text("\(profile.userPassword)").textSelection(.enabled)
					ShareLink(item: profile.userPassword, label: { Image(systemName: "square.on.square") })
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
		profile.receiveSharing(id: receivedId, 
							   password: receivedPassword,
							   completionHandler: { success, message in
			self.success = success
			self.message = message
			self.showStatus = true
		})
	}
}

#Preview {
    ShareProfileView()
}
