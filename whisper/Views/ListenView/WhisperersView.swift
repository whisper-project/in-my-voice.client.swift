// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import CoreBluetooth
import SwiftUI

struct WhisperersView: View {
    @Environment(\.colorScheme) var colorScheme
    
    @ObservedObject var model: ListenViewModel
    
    var body: some View {
        if model.whisperer == nil && model.candidates.isEmpty {
            Text("No Whisperers")
                .padding()
        } else {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(makeRows()) { row in
                    HStack(spacing: 5) {
                        Text(row.id)
                        if (row.remote.owner == .manual) {
                            Image(systemName: "network")
                        }
                    }
                    .frame(minWidth: 300)
                    .bold(row.isWhisperer)
                    .font(FontSizes.fontFor(FontSizes.minTextSize + 2))
                    .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                    .onTapGesture {
                        model.setWhisperer(row.remote)
                        model.showStatusDetail = false
                    }
                }
            }
            .padding()
        }
    }
    
    private struct Row: Identifiable, Comparable, Equatable {
        var id: String
        var remote: ListenViewModel.Remote
        var isWhisperer: Bool
        
        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.id < rhs.id
        }
        
        static func == (lhs: WhisperersView.Row, rhs: WhisperersView.Row) -> Bool {
            lhs.remote.id == rhs.remote.id
        }
    }
    
    private func makeRows() -> [Row] {
        if let whisperer = model.whisperer {
            return [Row(id: whisperer.name, remote: whisperer, isWhisperer: true)]
        } else {
            var rows = model.candidates.map { candidate in
                Row(id: candidate.name, remote: candidate, isWhisperer: false)
            }
            rows.sort()
            return rows
        }
    }
}

struct WhisperersView_Previews: PreviewProvider {
    static var previews: some View {
        WhisperersView(model: ListenViewModel(nil))
    }
}
