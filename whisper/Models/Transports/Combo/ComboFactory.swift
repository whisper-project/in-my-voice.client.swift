// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine

final class ComboFactory: TransportFactory {
    typealias Publisher = ComboWhisperTransport
    typealias Subscriber = ComboListenTransport
    
    static let shared = ComboFactory()
    
    var statusSubject: CurrentValueSubject<TransportStatus, Never> = .init(.on)
    
    func publisher(_ conversation: Conversation?) -> Publisher {
		guard let c = conversation else {
			fatalError("No conversation specified to publisher")
		}
        return Publisher(c)
    }
    
    func subscriber(_ conversation: Conversation?) -> Subscriber {
        return Subscriber(conversation)
    }
    
    //MARK: private types and properties and initialization
    private var autoFactory = BluetoothFactory.shared
    private var manualFactory = TcpFactory.shared
    
    private var autoStatus: TransportStatus = .on
    private var manualStatus: TransportStatus = .on

    private var cancellables: Set<AnyCancellable> = []

    init() {
        autoFactory.statusSubject
            .sink(receiveValue: setAutoStatus)
            .store(in: &cancellables)
        manualFactory.statusSubject
            .sink(receiveValue: setManualStatus)
            .store(in: &cancellables)
    }
    
    deinit {
        cancellables.cancel()
    }

    //MARK: private methods
    func setAutoStatus(_ new: TransportStatus) {
        autoStatus = new
        statusSubject.send(compositeStatus())
    }
    
    func setManualStatus(_ new: TransportStatus) {
        manualStatus = new
        statusSubject.send(compositeStatus())
    }
    
    private func compositeStatus() -> TransportStatus {
        switch autoStatus {
        case .off, .waiting:
            if case .on = manualStatus {
                #if targetEnvironment(simulator)
                // the simulator always has Bluetooth off,
                // so can't take accurate screenshots
                // unless we ignore this status
                return .on
                #else
                return .waiting
                #endif
            } else {
                return .off
            }
        case .disabled:
            if case .on = manualStatus {
                return .disabled
            } else {
                return .off
            }
        case .on:
            return .on
        }
    }
}
