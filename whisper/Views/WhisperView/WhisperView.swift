// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct WhisperView: View {
    @Binding var mode: OperatingMode
    
    var body: some View {
        VStack(spacing: 30) {
            Text("I'm whispering!")
            
            Button("Stop") {
                mode = .ask
            }
        }
    }
}

struct WhisperView_Previews: PreviewProvider {
    static let mode = Binding<OperatingMode>(get: { return .listen }, set: { _ in print("Stop") })
    
    static var previews: some View {
        WhisperView(mode: mode)
    }
}
