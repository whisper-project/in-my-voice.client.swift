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
        get { return TcpFactory.shared.publisherUrl }
    }
    
    func publisher(_ publisherUrl: TransportUrl) -> Publisher {
        return Publisher(publisherUrl)
    }
    
    func subscriber(_ publisherUrl: TransportUrl) -> Subscriber {
        return Subscriber(publisherUrl)
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
