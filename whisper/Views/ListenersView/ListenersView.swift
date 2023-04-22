// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import CoreBluetooth
import SwiftUI

struct ListenersView: View {
    @Environment(\.colorScheme) var colorScheme
    
    @ObservedObject var model: WhisperViewModel
    
    var body: some View {
        if model.listeners.isEmpty {
            Text("No Listeners")
        } else {
            VStack(alignment: .leading) {
                ForEach(makeRows()) { row in
                    HStack(spacing: 5) {
                        Text(row.id)
                        Spacer()
                        Button(action: { model.alertListener(row.central) }, label: { Image(systemName: "speaker.wave.2") })
                            .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 10))
                        Button(action: { model.dropListener(row.central) }, label: { Image(systemName: "delete.left") })
                    }
                    .font(FontSizes.fontFor(FontSizes.minTextSize))
                    .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                }
            }
            .padding()
        }
    }
    
    private struct Row: Identifiable, Comparable {
        var id: String
        var central: CBCentral

        static func < (lhs: ListenersView.Row, rhs: ListenersView.Row) -> Bool {
            lhs.id < rhs.id
        }
    }
    
    private func makeRows() -> [Row] {
        var rows = model.listeners.map({ central, pair in Row(id: pair.1, central: central) })
        rows.sort()
        return rows
    }
}

struct ListenersView_Previews: PreviewProvider {
    static var previews: some View {
        ListenersView(model: WhisperViewModel())
    }
}
