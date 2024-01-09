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
    @Binding var conversation: Conversation?
    @Binding var transportStatus: TransportStatus

    @State private var username: String = ""
    @State private var newUsername: String = ""
    @State private var showWhisperButtons = true
    @State private var credentialsMissing = false
    @State private var showWhisperConversations = false
    @State private var showListenConversations = false
    @FocusState private var nameEdit: Bool
    
    private let profile = UserProfile.shared
    
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
                        Link("Enable Bluetooth to listen...", destination: settingsUrl)
                            .font(FontSizes.fontFor(name: .normal))
                            .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                    case .waiting:
                        Text("Waiting for Bluetooth to listen...")
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
                                maybeWhisper(profile.whisperDefault)
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
                    .disabled(transportStatus != .on)
                    .simultaneousGesture(
                        LongPressGesture()
                            .onEnded { _ in
                                showListenConversations = true
                            }
                    )
                    .highPriorityGesture(
                        TapGesture()
                            .onEnded { _ in
                                conversation = nil
                                mode = .listen
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
            VStack (spacing: 10) {
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
                    HStack {
                        Spacer()
                        Button("About", action: {
                            let vc = SFSafariViewController(url: URL(string: website)!)
                            UIApplication.shared.firstKeyWindow?.rootViewController?.present(vc, animated: true)
                        })
                    }.frame(width: choiceButtonWidth)
                    Spacer().frame(width: choiceButtonWidth/3)
                    HStack {
                        Button("Support", action: {
                            let vc = SFSafariViewController(url: URL(string: "\(website)support.html")!)
                            UIApplication.shared.firstKeyWindow?.rootViewController?.present(vc, animated: true)
                        })
                        Spacer()
                    }.frame(width: choiceButtonWidth)
                }
            }
        }
        .alert("First Launch", isPresented: $credentialsMissing) {
            Button("OK") { }
        } message: {
            Text("Sorry, but on its first launch after installation the app needs a few minutes to connect to the whisper server. Please try again.")
        }
        .onAppear { updateFromProfile() }
        .onChange(of: nameEdit) { isEditing in
            if isEditing {
                withAnimation { showWhisperButtons = false }
            } else {
                updateOrRevertProfile()
            }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                logger.log("Reread user name going to choice view foreground")
                updateFromProfile()
            case .background, .inactive:
                break
            @unknown default:
                logger.error("Went to unknown phase: \(String(describing: newPhase))")
            }
        }
    }
    
    func updateFromProfile() {
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
    
    func maybeWhisper(_ c: Conversation?) {
        showWhisperConversations = false
        if let c = c {
            conversation = c
            mode = .whisper
        }
    }
    
    func maybeListen(_ c: Conversation?) {
        showListenConversations = false
        if let c = c {
            conversation = c
            mode = .listen
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
