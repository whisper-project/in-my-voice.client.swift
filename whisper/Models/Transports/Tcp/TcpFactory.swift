// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine

final class TcpFactory: TransportFactory {
    // MARK: protocol properties and methods
    typealias Publisher = TcpWhisperTransport
    typealias Subscriber = TcpListenTransport
    
    static let shared = TcpFactory()
    
    var statusSubject: CurrentValueSubject<TransportStatus, Never> = .init(.on)
    
    func publisher(_ publisherUrl: TransportUrl) -> Publisher {
        guard let url = publisherUrl else {
            fatalError("TCP whisper transport requires a whisper URL")
        }
        guard url.hasSuffix(PreferenceData.deviceId) else {
            fatalError("Tcp whisper transport can only publish on clientId channel")
        }
        return TcpWhisperTransport(url)
    }
    
    func subscriber(_ publisherUrl: TransportUrl) -> TcpListenTransport {
        guard let url = publisherUrl else {
            fatalError("TCP listen transport requires a whisper URL")
        }
        guard !url.hasSuffix(PreferenceData.deviceId) else {
            fatalError("TCP listen transport cannot listen to itself")
        }
        return TcpListenTransport(url)
    }
    
    //MARK: private types, properties, and initialization
    private var status: TransportStatus = .on
    private var tcpMonitor = TcpMonitor()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        tcpMonitor.statusSubject
            .sink(receiveValue: setStatus)
            .store(in: &cancellables)
    }
    
    deinit {
        cancellables.cancel()
    }
    
    private func setStatus(_ status: TransportStatus) {
        self.status = status
        statusSubject.send(status)
    }
}
