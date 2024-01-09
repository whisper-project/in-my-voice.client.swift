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
    
    func publisher(_ conversation: Conversation) -> Publisher {
        return Publisher(conversation)
    }
    
    func subscriber(_ conversation: Conversation?) -> Subscriber {
        return Subscriber(conversation)
    }
    
    //MARK: private types and properties and initialization
    private var localFactory = BluetoothFactory.shared
    private var globalFactory = TcpFactory.shared
    
    private var localStatus: TransportStatus = .on
    private var globalStatus: TransportStatus = .on

    private var cancellables: Set<AnyCancellable> = []

    init() {
        localFactory.statusSubject
            .sink(receiveValue: setLocalStatus)
            .store(in: &cancellables)
        globalFactory.statusSubject
            .sink(receiveValue: setGlobalStatus)
            .store(in: &cancellables)
    }
    
    deinit {
        cancellables.cancel()
    }

    //MARK: private methods
    func setLocalStatus(_ new: TransportStatus) {
        localStatus = new
        statusSubject.send(compositeStatus())
    }
    
    func setGlobalStatus(_ new: TransportStatus) {
        globalStatus = new
        statusSubject.send(compositeStatus())
    }
    
    private func compositeStatus() -> TransportStatus {
        switch localStatus {
        case .off, .waiting:
            if case .on = globalStatus {
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
            if case .on = globalStatus {
                return .disabled
            } else {
                return .off
            }
        case .on:
            return .on
        }
    }
}
