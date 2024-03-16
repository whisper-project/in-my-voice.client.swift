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

    @State private var newUsername: String = ""
    @State private var showWhisperButtons = true
    @State private var credentialsMissing = false
    @State private var showWhisperConversations = false
    @State private var showListenConversations = false
	@State private var showNoConnection = false
	@State private var showSharingSheet = false
    @FocusState private var nameEdit: Bool
	@StateObject private var profile = UserProfile.shared

    let nameWidth = CGFloat(350)
    let nameHeight = CGFloat(105)
    let choiceButtonWidth = CGFloat(140)
    let choiceButtonHeight = CGFloat(45)
    let website = "https://clickonetwo.github.io/whisper/"

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
                            .disabled(newUsername.isEmpty || newUsername == profile.username)
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
                    .background(profile.username == "" ? Color.gray : Color.accentColor)
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
								switch PreferenceData.whisperTapAction() {
								case "show":
									showWhisperConversations = true
								case "default":
									maybeWhisper(profile.whisperProfile.fallback)
								case "last":
									if let c = profile.whisperProfile.lastUsed {
										maybeWhisper(c)
									} else {
										showWhisperConversations = true
									}
								default:
									fatalError("Illegal preference value for Whisper tap action: \(PreferenceData.whisperTapAction())")
								}
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
								switch PreferenceData.listenTapAction() {
								case "show":
									showListenConversations = true
								case "last":
									if let c = profile.listenProfile.conversations().first {
										maybeListen(c)
									} else {
										showListenConversations = true
									}
								default:
									fatalError("Illegal preference value for Listen tap action: \(PreferenceData.listenTapAction())")
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
		.onChange(of: profile.timestamp, initial: true, updateFromProfile)
        .onChange(of: nameEdit) {
            if nameEdit {
                withAnimation { showWhisperButtons = false }
            } else {
                updateOrRevertProfile()
            }
        }
		.onChange(of: scenePhase) {
			if scenePhase == .active {
				logger.info("ChoiceView has become active")
				profile.update()
			}
		}
		.onAppear(perform: profile.update)
    }
    
    func updateFromProfile() {
        newUsername = profile.username
        if profile.username.isEmpty {
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
				profile.whisperProfile.lastUsed = c
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
