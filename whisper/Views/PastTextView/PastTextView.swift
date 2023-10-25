// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct PastTextView: View {
    var mode: OperatingMode
    @ObservedObject var model: PastTextModel
    
    @FocusState private var isEditing: Bool
    @State private var editing = false
    @State private var textEditorHeight : CGFloat = 20

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
                            if editing {
                                ZStack {
                                    Text(model.pastText)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(5)
                                        .foregroundColor(.clear)
                                        .background(GeometryReader {
                                            Color.clear.preference(key: ViewHeightKey.self,
                                                                   value: $0.frame(in: .local).size.height)
                                        })
                                    TextEditor(text: $model.pastText)
                                        .frame(height: textEditorHeight)
                                        .focused($isEditing)
                                }
                                .onPreferenceChange(ViewHeightKey.self) { textEditorHeight = $0 }
                                .id(1)
                            } else {
                                Text(model.pastText)
                                    .textSelection(.disabled)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .id(1)
                            }
                            if model.addLinesAtTop {
                                Spacer().id(2)
                            } else {
                                HStack { Spacer() }.id(2)
                            }
                        }
                        .frame(minWidth: gp.size.width, minHeight: gp.size.height, alignment: .leading)
                    }
                    .onAppear { self.scrollToEnd(sp) }
                    .onChange(of: model.pastText) { _ in self.scrollToEnd(sp) }
                }
                if mode == .whisper {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                editing.toggle()
                                isEditing = editing
                            }, label: {
                                if editing {
                                    Image(systemName: "pencil.slash")
                                        .foregroundColor(.accentColor)
                                        .background(Color(UIColor.systemBackground))
                                } else {
                                    Image(systemName: "pencil")
                                        .foregroundColor(.accentColor)
                                        .background(Color(UIColor.systemBackground))
                                }
                            })
                        }
                    }
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

struct ViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value = value + nextValue()
    }
}

struct PastTextView_Previews: PreviewProvider {
    static var model1 = PastTextModel(mode: .whisper, initialText: """
    Line 1 is short
    Line 2 is a bit longer
    Line 3 is extremely, long and\nit wraps
    Line 4 is short, getting descenders
    """)
    static var model2 = PastTextModel(mode: .listen, initialText: """
    Line 1 is short
    Line 2 is a bit longer
    Line 3 is extremely, long and\nit wraps
    Line 4 is short, getting descenders
    """)

    static var previews: some View {
        VStack {
            PastTextView(mode: .listen, model: model1)
                .frame(height: 350)
                .border(.black, width: 2)
            PastTextView(mode: .whisper, model: model2)
                .frame(height: 350)
                .border(.black, width: 2)
        }
    }
}
