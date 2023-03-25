// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct PastTextView: View {
    @ObservedObject var model: PastTextViewModel

    var body: some View {
        GeometryReader { gp in
            ScrollViewReader { sp in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading) {
                        Spacer()
                        ForEach(model.pastText) {
                            Text($0.text)
                                .id($0.id)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(minWidth: gp.size.width, minHeight: gp.size.height, alignment: .leading)
                }
                .onAppear {
                    if model.pastText.count > 0 {
                        sp.scrollTo(model.pastText.count - 1, anchor: .bottom)
                    }
                }
                .onChange(of: model.pastText.count) { _ in
                    if model.pastText.count > 0 {
                        sp.scrollTo(model.pastText.count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct PastTextView_Previews: PreviewProvider {
    static var model = PastTextViewModel(initialText: """
    Line 1 is short
    Line 2 is a bit longer
    Line 3 is extremely, long and\nit wraps
    Line 4 is short
    """)
    static var previews: some View {
        PastTextView(model: model)
    }
}
