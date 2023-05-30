// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Combine
import CoreBluetooth

final class MainViewModel: ObservableObject {
    @Published var state: CBManagerState = .unknown
    
    private var manager = BluetoothManager.shared
    private var cancellables: Set<AnyCancellable> = []
    
    init() {
        manager.stateSubject
            .sink(receiveValue: setState)
            .store(in: &cancellables)
    }
    
    deinit {
        cancellables.cancel()
    }
    
    private func setState(_ new: CBManagerState) {
        if new != state {
            logger.log("Bluetooth state changes to \(String(describing: new))")
            state = new
        } else {
            logger.log("Bluetooth state remains \(String(describing: new))")
        }
    }
}
