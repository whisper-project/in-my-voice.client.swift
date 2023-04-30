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
        if model.whisperer == nil && candidates().isEmpty {
            Text("No Whisperers")
                .padding()
        } else {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(makeRows()) { row in
                    Text(row.id)
                        .bold(row.isWhisperer)
                        .font(FontSizes.fontFor(FontSizes.minTextSize + 2))
                        .foregroundColor(colorScheme == .light ? lightPastTextColor : darkPastTextColor)
                        .onTapGesture {
                            model.setWhisperer(to: row.peripheral)
                            model.showStatusDetail = false
                        }
                }
            }
            .padding()
        }
    }
    
    private struct Row: Identifiable, Comparable {
        var id: String
        var peripheral: CBPeripheral
        var isWhisperer: Bool
        
        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.id < rhs.id
        }
    }
    
    private func makeRows() -> [Row] {
        if let whisperer = model.whisperer {
            return [Row(id: whisperer.name, peripheral: whisperer.peripheral, isWhisperer: true)]
        } else {
            var rows = candidates().map { candidate in
                Row(id: candidate.name, peripheral: candidate.peripheral, isWhisperer: false)
            }
            rows.sort()
            return rows
        }
    }
    
    private func candidates() -> [ListenViewModel.Whisperer] {
        return model.candidates.values.filter { $0.canBeWhisperer() }
    }
}

struct WhisperersView_Previews: PreviewProvider {
    static var previews: some View {
        WhisperersView(model: ListenViewModel())
    }
}
