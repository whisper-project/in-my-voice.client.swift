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
        if model.eligibleCandidates().isEmpty {
            Text("No Whisperers")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(makeRows()) { row in
                    HStack(spacing: 5) {
                        Text(row.id)
                            .bold(row.isPrimary)
                        Spacer()
                        Button(action: { model.switchPrimary(to: row.peripheral) }, label: { Image(systemName: "ear.badge.checkmark") })
                            .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
                            .disabled(row.isPrimary)
                    }
                    .font(FontSizes.fontFor(FontSizes.minTextSize + 2))
                    .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                }
            }
            .padding()
        }
    }
    
    private struct Row: Identifiable, Comparable {
        var id: String
        var peripheral: CBPeripheral
        var isPrimary: Bool
        
        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.id < rhs.id
        }
    }
    
    private func makeRows() -> [Row] {
        var rows = model.eligibleCandidates().map({ candidate in
            Row(id: candidate.name, peripheral: candidate.peripheral, isPrimary: candidate.isPrimary)
        })
        rows.sort()
        return rows
    }
}

struct WhisperersView_Previews: PreviewProvider {
    static var previews: some View {
        WhisperersView(model: ListenViewModel())
    }
}
