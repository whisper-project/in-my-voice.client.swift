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
            NavigationView {
                List {
					ForEach(conversations) { c in
						NavigationLink(destination: WhisperProfileDetailView(c: c)) {
							HStack(spacing: 15) {
								Text(c.name)
									.lineLimit(nil)
									.bold(c == defaultConversation)
								Spacer(minLength: 25)
								Button("Whisper", systemImage: "icloud.and.arrow.up") {
									logger.info("Hit whisper button on \(c.id) (\(c.name))")
									maybeWhisper?(c)
								}
								.labelStyle(.iconOnly)
								.buttonStyle(.bordered)
							}
						}
					}
					.onDelete { indexSet in
						indexSet.forEach{ profile.deleteWhisperConversation(conversations[$0]) }
						updateProfile()
					}
                }
            }
			.navigationTitle("Conversations")
			.toolbar {
				EditButton()
				Button(action: addConversation, label: { Text("Add") } )
			}
        }
        .padding(10)
        .onAppear {
            updateFromProfile()
        }
    }

	func addConversation() {
		logger.info("Creating new conversation")
		profile.addWhisperConversation()
		updateProfile()
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
