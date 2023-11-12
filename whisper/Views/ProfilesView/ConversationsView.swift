// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct ConversationsView: View {
    var maybeWhisper: ((Conversation?) -> Void)?
    
    @State private var conversations: [Conversation] = []
    @State private var defaultConversation: Conversation?
    
    static let legend1 = "\(Image(systemName: "icloud.and.arrow.up")) = Whisper"
    static let legend2 = "\(Image(systemName: "checkmark.square")) = Set Default"
    static let legend3 = "\(Image(systemName: "delete.left")) = Delete"
    static let legend = "\(legend1), \(legend2), \(legend3)"

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Text("\(Image(systemName: "icloud.and.arrow.up")) = Whisper, \(Image(systemName: "checkmark.square")) = Set Default, \(Image(systemName: "delete.left")) = Delete")
                .font(FontSizes.fontFor(name: .small))
            VStack(alignment: .leading) {
                ForEach($conversations) { $c in
                    HStack(spacing: 20) {
                        TextField("Name", text: $c.name)
                            .bold(c == defaultConversation)
                            .submitLabel(.done)
                            .onSubmit { updateProfile() }
                        Spacer(minLength: 25)
                        Button("Whisper", systemImage: "icloud.and.arrow.up") {
                            logger.info("Hit whisper button on \(c.name) (\(c.id))")
                            updateProfile()
                            maybeWhisper?(c)
                        }
                        .labelStyle(.iconOnly)
                        Button("Set Default", systemImage: "checkmark.square") {
                            logger.info("Hit set default button on \(c.name) (\(c.id))")
                            UserProfile.shared.defaultConversation = c
                            updateProfile()
                        }
                        .labelStyle(.iconOnly)
                        .disabled(c == defaultConversation)
                        Button("Delete", systemImage: "delete.left") {
                            logger.info("Hit delete button on \(c.name) (\(c.id))")
                            UserProfile.shared.deleteConversation(c)
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
                    UserProfile.shared.newConversation()
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
        conversations = UserProfile.shared.conversations
        defaultConversation = UserProfile.shared.defaultConversation
    }
    
    func updateProfile() {
        UserProfile.shared.saveAsDefault()
        updateFromProfile()
    }
}

#Preview {
    ConversationsView()
}
