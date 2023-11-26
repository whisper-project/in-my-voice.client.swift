// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct WhisperProfileView: View {
    var maybeWhisper: ((Conversation?) -> Void)?
    
    @State private var conversations: [Conversation] = []
    @State private var defaultConversation: Conversation?
        
    private let profile = UserProfile.shared
    
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Text("\(Image(systemName: "icloud.and.arrow.up")) = Whisper, \(Image(systemName: "checkmark.square")) = Set Default, \(Image(systemName: "delete.left")) = Delete")
                .font(FontSizes.fontFor(name: .small))
            VStack(alignment: .leading) {
                ForEach($conversations) { $c in
                    HStack(spacing: 15) {
                        TextField("Name", text: $c.name)
                            .allowsTightening(true)
                            .bold(c == defaultConversation)
                            .submitLabel(.done)
                            .onSubmit { updateProfile() }
                        Spacer(minLength: 25)
                        Button("Whisper", systemImage: "icloud.and.arrow.up") {
                            logger.info("Hit whisper button on \(c.id) (\(c.name))")
                            updateProfile()
                            maybeWhisper?(c)
                        }
                        .labelStyle(.iconOnly)
                        Button("Set Default", systemImage: "checkmark.square") {
                            logger.info("Hit set default button on \(c.id) (\(c.name))")
                            profile.whisperDefault = c
                            updateProfile()
                        }
                        .labelStyle(.iconOnly)
                        .disabled(c == defaultConversation)
                        Button("Delete", systemImage: "delete.left") {
                            logger.info("Hit delete button on \(c.id) (\(c.name))")
                            profile.deleteWhisperConversation(c)
                            updateProfile()
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    logger.info("Canceling whisper conversation choice")
                    updateProfile()
                    maybeWhisper?(nil)
                }
                Spacer()
                Button("New") {
                    logger.info("Creating new conversation")
                    profile.addWhisperConversation()
                    updateProfile()
                }
                Spacer()
            }
        }
        .padding(10)
        .onAppear {
            updateFromProfile()
        }
    }
    
    func updateFromProfile() {
        conversations = profile.whisperConversations()
        defaultConversation = profile.whisperDefault
    }
    
    func updateProfile() {
        profile.saveAsDefault()
        updateFromProfile()
    }
}

#Preview {
    WhisperProfileView()
}
