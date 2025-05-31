// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Combine
import CoreBluetooth

final class MainViewModel: ObservableObject {
    @Published var message: String = ""
	@Published var showMessage: Bool = false

    private var cancellables: Set<AnyCancellable> = []
    
    init() {
        ServerProtocol.messageSubject
            .sink(receiveValue: setMessage)
            .store(in: &cancellables)
    }
    
    deinit {
        cancellables.cancel()
    }
    
    private func setMessage(_ new: String?) {
		guard let new = new else {
			return
		}
		DispatchQueue.main.async {
			self.message = new
			self.showMessage = true
		}
    }
}
