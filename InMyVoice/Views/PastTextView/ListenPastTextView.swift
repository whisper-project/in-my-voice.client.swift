// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct ListenPastTextView: View {
    @ObservedObject var model: PastTextModel
    
    var body: some View {
        GeometryReader { gp in
            ZStack {
                ScrollViewReader { sp in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading) {
                            if model.addLinesAtTop {
                                HStack { Spacer() }.id(0)
                            } else {
                                Spacer().id(0)
                            }
							Text(.init(model.pastText))
								.textSelection(.disabled)
								.lineLimit(nil)
								.fixedSize(horizontal: false, vertical: true)
								.id(1)
                            if model.addLinesAtTop {
                                Spacer().id(2)
                            } else {
                                HStack { Spacer() }.id(2)
                            }
                        }
                        .frame(minWidth: gp.size.width, minHeight: gp.size.height, alignment: .leading)
                    }
                    .onAppear { self.scrollToEnd(sp) }
                    .onChange(of: model.pastText) { self.scrollToEnd(sp) }
                }
            }
        }
    }
    
    func scrollToEnd(_ sp: ScrollViewProxy) {
        if model.addLinesAtTop {
            sp.scrollTo(0, anchor: .top)
        } else {
            sp.scrollTo(2, anchor: .bottom)
        }
    }
}
