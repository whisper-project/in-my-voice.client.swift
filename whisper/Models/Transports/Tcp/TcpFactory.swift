// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import Combine

let controlChannelPacketRepeatCount: Int = {
	guard let count = ProcessInfo.processInfo.environment["WHISPER_CONTROL_CHANNEL_REPEAT_COUNT"] else {
		return 1
	}
	guard let parsed = Int(count) else {
		return 1
	}
	return parsed > 1 ? parsed : 1
}()

final class TcpFactory: TransportFactory {
    // MARK: protocol properties and methods
    typealias Publisher = TcpWhisperTransport
    typealias Subscriber = TcpListenTransport
    
    static let shared = TcpFactory()

    var statusSubject: CurrentValueSubject<TransportStatus, Never> = .init(.on)
    
    func publisher(_ conversation: WhisperConversation) -> Publisher {
        return TcpWhisperTransport(conversation)
    }
    
    func subscriber(_ conversation: ListenConversation?) -> Subscriber {
        guard let c = conversation else {
            fatalError("TCP listen transport requires a whisper URL")
        }
        return TcpListenTransport(c)
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
		#if DISABLE_INTERNET
		self.status = .off
		#else
        self.status = status
		#endif
        statusSubject.send(status)
    }
}
