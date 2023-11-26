// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct ListenProfileView: View {
    var maybeListen: ((Conversation?) -> Void)?
    
    @State private var conversations: [Conversation] = []
        
    private let profile = UserProfile.shared
    
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Text("\(Image(systemName: "icloud.and.arrow.down")) = Listen, \(Image(systemName: "delete.left")) = Delete")
                .font(FontSizes.fontFor(name: .small))
            if (!conversations.isEmpty) {
                VStack(alignment: .leading) {
                    ForEach($conversations) { $c in
                        HStack(spacing: 20) {
                            TextField("Name", text: $c.name)
                                .submitLabel(.done)
                                .onSubmit { updateProfile() }
                            Spacer(minLength: 25)
                            Button("Listen", systemImage: "icloud.and.arrow.down") {
                                logger.info("Hit listen button on \(c.id) (\(c.name))")
                                updateProfile()
                                maybeListen?(c)
                            }
                            .labelStyle(.iconOnly)
                            Button("Delete", systemImage: "delete.left") {
                                logger.info("Hit delete button on \(c.id) (\(c.name))")
                                profile.deleteListenConversation(c)
                                updateProfile()
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
            } else {
                Text("(No past conversations to choose from.)")
                    .padding()
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    logger.info("Canceling whisper conversation choice")
                    updateProfile()
                    maybeListen?(nil)
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
        conversations = profile.listenConversations()
    }
    
    func updateProfile() {
        profile.saveAsDefault()
        updateFromProfile()
    }
}

#Preview {
    ListenProfileView()
}
