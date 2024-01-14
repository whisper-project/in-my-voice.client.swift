// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct ListenProfileView: View {
	#if targetEnvironment(macCatalyst)
	@Environment(\.dismiss) private var dismiss
	#endif

	var maybeListen: ((Conversation?) -> Void)?

    @State private var conversations: [Conversation] = []
        
    private let profile = UserProfile.shared
    
    var body: some View {
		NavigationStack {
			VStack(alignment: .center, spacing: 20) {
				if (!conversations.isEmpty) {
					VStack(alignment: .leading) {
						ForEach(conversations) { c in
							HStack(spacing: 20) {
								Text("\(c.name) with \(c.ownerName)").lineLimit(nil)
								Spacer(minLength: 25)
								Button("Listen", systemImage: "icloud.and.arrow.down") {
									logger.info("Hit listen button on \(c.id) (\(c.name))")
									maybeListen?(c)
								}
								Button("Delete", systemImage: "delete.left") {
									logger.info("Hit delete button on \(c.id) (\(c.name))")
									profile.deleteListenConversation(c.id)
									updateFromProfile()
								}
							}
							.labelStyle(.iconOnly)
							.buttonStyle(.borderless)
						}
						Spacer()
					}
				} else {
					Text("(No past conversations)")
						.padding()
				}
			}
			.toolbarTitleDisplayMode(.large)
			.navigationTitle("Conversations")
			#if targetEnvironment(macCatalyst)
			.toolbar {
				Button(action: { dismiss() }, label: { Text("Close") } )
			}
			#endif
			.padding(10)
			.onAppear {
				updateFromProfile()
			}
		}
    }
    
    func updateFromProfile() {
        conversations = profile.listenConversations()
    }
}

#Preview {
    ListenProfileView()
}
