// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI
import SafariServices


struct ChoiceView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    @Binding var mode: OperatingMode
	@Binding var conversation: (any Conversation)?
    @Binding var transportStatus: TransportStatus

    @State private var username: String = ""
    @State private var newUsername: String = ""
    @State private var showWhisperButtons = true
    @State private var credentialsMissing = false
    @State private var showWhisperConversations = false
    @State private var showListenConversations = false
	@State private var showNoConnection = false
	@State private var showSharingSheet = false
    @FocusState private var nameEdit: Bool
    
    let nameWidth = CGFloat(350)
    let nameHeight = CGFloat(105)
    let choiceButtonWidth = CGFloat(140)
    let choiceButtonHeight = CGFloat(45)
    let website = "https://clickonetwo.github.io/whisper/"

	let profile = UserProfile.shared

    var body: some View {
        VStack(spacing: 40) {
            Form {
                Section(header: Text("Your Name")) {
                    HStack {
                        TextField("Your Name", text: $newUsername, prompt: Text("Fill in to continue…"))
                            .submitLabel(.done)
                            .focused($nameEdit)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .allowsTightening(true)
                        Button("Submit", systemImage: "checkmark.square.fill") { nameEdit = false }
                            .labelStyle(.iconOnly)
                            .disabled(newUsername.isEmpty || newUsername == username)
                    }
                }
            }
            .frame(maxWidth: nameWidth, maxHeight: nameHeight)
            if (showWhisperButtons) {
                if transportStatus != .on {
                    switch transportStatus {
                    case .off:
                        Link("Enable Bluetooth or Wireless to whisper or listen...", destination: settingsUrl)
                            .font(FontSizes.fontFor(name: .normal))
                            .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                    case .disabled:
                        Link("Bluetooth not enabled, Wireless available", destination: settingsUrl)
                            .font(FontSizes.fontFor(name: .normal))
                            .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                    case .waiting:
                        Text("Waiting for Bluetooth, Wireless available")
                            .font(FontSizes.fontFor(name: .normal))
                            .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                    case .on:
                        fatalError("Can't happen")
                    }
                }
                HStack(spacing: 30) {
                    Button(action: {}) {
                        Text("Whisper")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .frame(width: choiceButtonWidth, height: choiceButtonHeight, alignment: .center)
                    }
                    .background(username == "" ? Color.gray : Color.accentColor)
                    .cornerRadius(15)
                    .disabled(transportStatus == .off)
                    .simultaneousGesture(
                        LongPressGesture()
                            .onEnded { _ in
                                showWhisperConversations = true
                            }
                    )
                    .highPriorityGesture(
                        TapGesture()
                            .onEnded { _ in
								maybeWhisper(profile.whisperProfile.fallback)
                            }
                    )
                    .sheet(isPresented: $showWhisperConversations) {
                        WhisperProfileView(maybeWhisper: maybeWhisper)
                    }
                    Button(action: {}) {
                        Text("Listen")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .frame(width: choiceButtonWidth, height: choiceButtonHeight, alignment: .center)
                    }
                    .background(Color.accentColor)
                    .cornerRadius(15)
					.disabled(transportStatus == .off)
                    .simultaneousGesture(
                        LongPressGesture()
                            .onEnded { _ in
                                showListenConversations = true
                            }
                    )
                    .highPriorityGesture(
                        TapGesture()
                            .onEnded { _ in
								if transportStatus == .on {
									conversation = nil
									mode = .listen
								} else {
									showListenConversations = true
								}
                            }
                    )
                    .sheet(isPresented: $showListenConversations) {
                        ListenProfileView(maybeListen: maybeListen)
                    }
                }
                .transition(.scale)
            }
            Button(action: {
                UIApplication.shared.open(settingsUrl)
            }) {
                Text("Settings")
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                    .frame(width: choiceButtonWidth, height: choiceButtonHeight, alignment: .center)
            }
            .background(Color.accentColor)
            .cornerRadius(15)
            VStack (spacing: 40) {
                Button(action: {
                    let vc = SFSafariViewController(url: URL(string: "\(website)instructions.html")!)
                    UIApplication.shared.firstKeyWindow?.rootViewController?.present(vc, animated: true)
                }) {
                    Text("How To Use")
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                        .frame(width: choiceButtonWidth, height: choiceButtonHeight, alignment: .center)
                }
                .background(Color.accentColor)
                .cornerRadius(15)
                HStack {
					Button("Profile Sharing", action: { showSharingSheet = true })
						.sheet(isPresented: $showSharingSheet, content: { ShareProfileView() })
					Spacer()
					Button("About", action: {
						let vc = SFSafariViewController(url: URL(string: website)!)
						UIApplication.shared.firstKeyWindow?.rootViewController?.present(vc, animated: true)
					})
                    Spacer()
					Button("Support", action: {
						let vc = SFSafariViewController(url: URL(string: "\(website)support.html")!)
						UIApplication.shared.firstKeyWindow?.rootViewController?.present(vc, animated: true)
					})
				}.frame(width: nameWidth)
            }
        }
        .alert("First Launch", isPresented: $credentialsMissing) {
            Button("OK") { }
        } message: {
            Text("Sorry, but on its first launch after installation the app needs a few minutes to connect to the whisper server. Please try again.")
        }
		.alert("No Connection", isPresented: $showNoConnection) {
			Button("OK") { }
		} message: {
			Text("You must enable a Bluetooth and/or Wireless connection before you can whisper or listen")
		}
        .onAppear { updateFromProfile() }
        .onChange(of: nameEdit) {
            if nameEdit {
                withAnimation { showWhisperButtons = false }
            } else {
                updateOrRevertProfile()
            }
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                logger.log("Reread user name going to choice view foreground")
                updateFromProfile()
            case .background, .inactive:
                break
            @unknown default:
                logger.error("Went to unknown phase: \(String(describing: scenePhase))")
            }
        }
    }
    
    func updateFromProfile() {
		profile.update()
        username = profile.username
        newUsername = username
        if username.isEmpty {
        withAnimation {
                showWhisperButtons = false
                nameEdit = true
            }
        }
    }
    
    func updateOrRevertProfile() {
        let proposal = newUsername.trimmingCharacters(in: .whitespaces)
        if proposal.isEmpty {
            updateFromProfile()
        } else {
            newUsername = proposal
            username = proposal
            profile.username = proposal
            withAnimation {
                showWhisperButtons = true
            }
        }
    }
    
    func maybeWhisper(_ c: WhisperConversation?) {
        showWhisperConversations = false
		if let c = c {
			if transportStatus == .off {
				showNoConnection = true
			} else {
				conversation = c
				mode = .whisper
			}
		}
    }
    
    func maybeListen(_ c: ListenConversation?) {
        showListenConversations = false
		if let c = c {
			if transportStatus == .off {
				showNoConnection = true
			} else {
				conversation = c
				mode = .listen
			}
		}
    }
}

extension UIApplication {
    var firstKeyWindow: UIWindow? {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .first?.keyWindow
    }
}

#Preview {
    ChoiceView(mode: makeBinding(.ask),
               conversation: makeBinding(nil),
               transportStatus: makeBinding(.on))
}
