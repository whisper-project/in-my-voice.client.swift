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
    
    var publisherUrl: TransportUrl {
        return TcpFactory.shared.publisherUrl
    }
    
    func publisher(_ publisherUrl: TransportUrl) -> Publisher {
        return Publisher(publisherUrl)
    }
    
    func subscriber(_ publisherUrl: TransportUrl) -> Subscriber {
        return Subscriber(publisherUrl)
    }
    
    //MARK: private types and properties and initialization
#if targetEnvironment(simulator)
    private var autoFactory = DribbleFactory.shared
#else
    private var autoFactory = BluetoothFactory.shared
#endif
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
        case .off(let message):
            return .off(message)
        case .disabled(let message):
            return .disabled(message)
        case .on:
            switch manualStatus {
            case .off(let message):
                return .off(message)
            case .disabled(let message):
                return .disabled(message)
            case .on:
                return .on
            }
        }
    }
}
