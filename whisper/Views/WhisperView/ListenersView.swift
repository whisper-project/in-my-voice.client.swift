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
        if model.remotes.isEmpty {
            Text("No Listeners")
        } else {
            VStack(alignment: .leading) {
                ForEach(makeRows()) { row in
                    HStack(spacing: 5) {
                        Text(row.id)
                        Spacer()
                        Button(action: { model.playSound(row.remote) }, label: { Image(systemName: "speaker.wave.2") })
                            .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 10))
                        Button(action: { model.dropListener(row.remote) }, label: { Image(systemName: "delete.left") })
                    }
                    .font(FontSizes.fontFor(FontSizes.minTextSize))
                    .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                }
            }
            .padding()
        }
    }
    
    private struct Row: Identifiable, Comparable, Equatable {
        var id: String
        var remote: WhisperViewModel.Remote

        static func == (lhs: Row, rhs: Row) -> Bool {
            lhs.id == rhs.id
        }
        
        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.id < rhs.id
        }
    }
    
    private func makeRows() -> [Row] {
        var rows: [Row] = []
        for remote in model.remotes.values {
            rows.append(Row(id: remote.name, remote: remote))
        }
        rows.sort()
        return rows
    }
}

struct ListenersView_Previews: PreviewProvider {
    static var previews: some View {
        ListenersView(model: WhisperViewModel())
    }
}
