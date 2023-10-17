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
    
    var publisherUrl: TransportUrl {
        get {
            if case .on = status {
                return "\(PreferenceData.whisperServer)/subscribe/\(PreferenceData.clientId)"
            } else {
                return nil
            }
        }
    }
    
    func publisher(_ publisherUrl: TransportUrl) -> Publisher {
        guard publisherUrl == self.publisherUrl else {
            fatalError("This client's TCP publisherUrl is not \(String(describing: publisherUrl))")
        }
        return TcpWhisperTransport(publisherUrl!)
    }
    
    func subscriber(_ publisherUrl: TransportUrl) -> TcpListenTransport {
        guard let url = publisherUrl else {
            fatalError("TCP listen transport requires a whisper URL")
        }
        guard !url.hasSuffix(PreferenceData.clientId) else {
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
