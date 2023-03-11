// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Combine
import CoreBluetooth

enum OperatingMode: Int {
    case ask = 0, listen = 1, whisper = 2
}

final class MainViewModel: ObservableObject {
    @Published var state: CBManagerState = .poweredOn
    
    private var manager = BluetoothManager.shared
    private var cancellables: Set<AnyCancellable> = []
    
    init() {
        manager.stateSubject
            .filter{ [weak self] in self?.state != $0 }
            .sink{ [weak self] in self?.state = $0 }
            .store(in: &cancellables)
    }
    
    deinit {
        cancellables.cancel()
    }
    
    static func get_initial_mode() -> OperatingMode {
        let defaults = UserDefaults.standard
        let val = defaults.integer(forKey: "initial_mode_preference")
        return OperatingMode(rawValue: val) ?? .ask
    }
    
    static func save_initial_mode(_ mode: OperatingMode) {
        let defaults = UserDefaults.standard
        defaults.set(mode.rawValue, forKey: "initial_mode_preference")
    }
}
