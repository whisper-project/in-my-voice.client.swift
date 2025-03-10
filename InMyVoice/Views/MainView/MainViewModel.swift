// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Combine
import CoreBluetooth

final class MainViewModel: ObservableObject {
    @Published var status: TcpStatus = .on
    
    private var factory = ComboFactory.shared
    private var cancellables: Set<AnyCancellable> = []
    
    init() {
        self.factory.statusSubject
            .sink(receiveValue: setStatus)
            .store(in: &cancellables)
    }
    
    deinit {
        cancellables.cancel()
    }
    
    private func setStatus(_ new: TcpStatus) {
        status = new
    }
}
