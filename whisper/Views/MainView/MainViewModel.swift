// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Combine
import CoreBluetooth

final class MainViewModel: ObservableObject {
    @Published var status: TransportStatus = .on
    
    private var autoTransport: (any TransportFactory)!
    private var cancellables: Set<AnyCancellable> = []
    
    init() {
        #if targetEnvironment(simulator)
        self.autoTransport = DribbleFactory.shared
        #else
        self.autoTransport = BluetoothFactory.shared
        #endif
        self.autoTransport.statusSubject
            .sink(receiveValue: setStatus)
            .store(in: &cancellables)
    }
    
    deinit {
        cancellables.cancel()
    }
    
    private func setStatus(_ new: TransportStatus) {
        status = new
    }
}
