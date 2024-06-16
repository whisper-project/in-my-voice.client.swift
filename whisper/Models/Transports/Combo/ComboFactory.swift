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
    
    var statusSubject: CurrentValueSubject<TransportStatus, Never> = .init(.off)

    func publisher(_ conversation: WhisperConversation) -> Publisher {
        return Publisher(conversation)
    }
    
    func subscriber(_ conversation: ListenConversation) -> Subscriber {
        return Subscriber(conversation)
    }
    
    //MARK: private types and properties and initialization
    private var localFactory = BluetoothFactory.shared
    private var globalFactory = TcpFactory.shared
    
    private var localStatus: TransportStatus = .off
    private var globalStatus: TransportStatus = .off

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
		case .off:
			return globalStatus == .on ? .globalOnly : .off
		case .waiting:
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
			return globalStatus == .on ? .disabled : .off
        case .on:
			return globalStatus == .on ? .on : .localOnly
		default:
			logAnomaly("Can't happen: localStatus was \(localStatus), assuming .off")
			return globalStatus == .on ? .globalOnly : .off
        }
    }
}
