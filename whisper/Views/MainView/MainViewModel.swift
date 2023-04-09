// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Combine
import CoreBluetooth

enum OperatingMode: Int {
    case ask = 0, listen = 1, whisper = 2
}

let modePreferenceKey = "initial_mode_preference"

final class MainViewModel: ObservableObject {
    @Published var state: CBManagerState = .unknown
    @Published var mode: OperatingMode = .ask
    
    private var manager = BluetoothManager.shared
    private var cancellables: Set<AnyCancellable> = []
    private let defaults = UserDefaults.standard
    
    init() {
        manager.stateSubject
            .sink(receiveValue: setState)
            .store(in: &cancellables)
        let val = defaults.integer(forKey: modePreferenceKey)
        mode = OperatingMode(rawValue: val) ?? .ask
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
    
    func setMode(_ mode: OperatingMode, always: Bool = false) {
        self.mode = mode
        if always {
            defaults.set(mode.rawValue, forKey: modePreferenceKey)
        } else {
            defaults.set(OperatingMode.ask.rawValue, forKey: modePreferenceKey)
        }
    }
}
