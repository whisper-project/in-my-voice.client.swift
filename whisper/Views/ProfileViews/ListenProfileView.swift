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
							VStack(spacing: 0) {
								Text("\(c.name) with \(c.ownerName)")
								HStack(spacing: 20) {
									Button("Listen") {
										logger.info("Hit listen button on \(c.id) (\(c.name))")
										maybeListen?(c)
									}
									Spacer()
									Button("Delete") {
										logger.info("Hit delete button on \(c.id) (\(c.name))")
										profile.deleteListenConversation(c.id)
										updateFromProfile()
									}
								}
								.buttonStyle(.borderless)
							}
						}
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
