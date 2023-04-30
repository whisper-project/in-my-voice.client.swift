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
        if model.whisperers().isEmpty {
            Text("No Whisperers")
                .padding()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(makeRows()) { row in
                    HStack(spacing: 5) {
                        Text(row.id)
                        Spacer()
                        Button(action: { model.setWhisperer(to: row.peripheral) }, label: { Image(systemName: "ear.badge.checkmark") })
                            .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
                            .disabled(row.isSelected)
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
        var isSelected: Bool
        
        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.id < rhs.id
        }
    }
    
    private func makeRows() -> [Row] {
        let whisperers = model.whisperers()
        let count = whisperers.count
        return whisperers.map({ candidate in
            Row(id: candidate.name, peripheral: candidate.peripheral, isSelected: count == 1)
        })
    }
}

struct WhisperersView_Previews: PreviewProvider {
    static var previews: some View {
        WhisperersView(model: ListenViewModel())
    }
}
