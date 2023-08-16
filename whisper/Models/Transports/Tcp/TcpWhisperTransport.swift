// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Combine
import Ably

final class TcpWhisperTransport: WhisperTransport {    
    typealias TransportRemote = ProxyListener
    
    final class ProxyListener {
        var id: String
        var name: String
        
        init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }
    
    let discoveryType: TransportDiscovery = .manual(WhisperData.deviceId)
    
    var statusSubject: CurrentValueSubject<TransportStatus, Never> = .init(.on)
    var addRemoteSubject: PassthroughSubject<ProxyListener, Never> = .init()
    var dropRemoteSubject: PassthroughSubject<ProxyListener, Never> = .init()

    func start() {
        <#code#>
    }
    
    func stop() {
        <#code#>
    }
    
    func goToBackground() {
        <#code#>
    }
    
    func goToForeground() {
        <#code#>
    }
    
    func sendChunks(chunks: [TextProtocol.ProtocolChunk]) {
        <#code#>
    }
}
