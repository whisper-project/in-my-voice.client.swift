// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import SwiftJWT
import Ably

enum TcpAuthenticatorError: Error {
    case local(String)
    case server(String)
}

final class TcpAuthenticator {
    private var mode: OperatingMode
    private var publisherId: String
    private var clientId = PreferenceData.clientId
    private var client: ARTRealtime?
    private var failureCallback: (String) -> Void
    
    init(mode: OperatingMode, publisherId: String, callback: @escaping (String) -> Void) {
        self.mode = mode
        self.publisherId = publisherId
        self.failureCallback = callback
    }
    
    func getClient() -> ARTRealtime {
        if let client = self.client {
            return client
        }
        let options = ARTClientOptions()
        options.clientId = self.clientId
        options.authCallback = getTokenRequest
        options.autoConnect = true
        options.echoMessages = false
        let client = ARTRealtime(options: options)
        self.client = client
        return client
    }
    
    struct ClientClaims: Claims {
        let iss: String
        let exp: Date
    }
    
    func createJWT() -> String? {
        guard let secret = PreferenceData.clientSecret(),
              let secretData = Data(base64Encoded: Data(secret.utf8)) else {
            logger.error("No secret data received from whisper-server")
            failureCallback("Can't receive notifications from the whisper server.  Please quit and restart the app.")
            return nil
        }
        let claims = ClientClaims(iss: clientId, exp: Date(timeIntervalSinceNow: 3600))
        var jwt = JWT(claims: claims)
        let signer = JWTSigner.hs256(key: secretData)
        let signedJWT = try? jwt.sign(using: signer)
        return signedJWT
    }
    
    func getTokenRequest(params: ARTTokenParams, callback: @escaping ARTTokenDetailsCompatibleCallback) {
        if let requestClientId = params.clientId,
           requestClientId != self.clientId
        {
            logger.warning("Token request client \(requestClientId) doesn't match authenticator client \(self.clientId)")
        }
        guard let jwt = createJWT() else {
            logger.error("Couldn't create JWT to post token request")
            callback(nil, TcpAuthenticatorError.local("Can't create JWT"))
            return
        }
        let activity = mode == .whisper ? "publish" : "subscribe"
        let value = [
            "clientId": clientId,
            "activity": mode == .whisper ? "publish" : "subscribe",
            "publisherId": publisherId
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: value) else {
            fatalError("Can't encode body for \(activity) token request call")
        }
        guard let url = URL(string: PreferenceData.whisperServer + "/api/pubSubTokenRequest") else {
            fatalError("Can't create URL for \(activity) token request call")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + jwt, forHTTPHeaderField: "Authorization")
        request.httpBody = body
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            guard error == nil else {
                logger.error("Failed to post \(activity) token request: \(String(describing: error))")
                self.failureCallback("Can't contact the whisper server.  Please make sure your network is working and restart the app.")
                callback(nil, error)
                return
            }
            guard let response = response as? HTTPURLResponse else {
                logger.error("Received non-HTTP response on \(activity) token request: \(String(describing: response))")
                self.failureCallback("Having trouble with the whisper server.  Please try again.")
                callback(nil, TcpAuthenticatorError.server("Non-HTTP response"))
                return
            }
            if response.statusCode == 403 {
                logger.error("Received forbidden response status on \(activity) token request.")
                self.failureCallback("Can't authenticate with the whisper server.  Please uninstall and reinstall the app.")
                return
            }
            if response.statusCode != 200 {
                logger.warning("Received unexpected response status on \(activity) token request: \(response.statusCode)")
            }
            guard let data = data,
                  let body = try? JSONSerialization.jsonObject(with: data),
                  let obj = body as? [String:String] else {
                logger.error("Can't deserialize \(activity) token response body: \(String(describing: data))")
                self.failureCallback("Having trouble with the whisper server.  Please try again later.")
                callback(nil, TcpAuthenticatorError.server("Non-JSON response to token request"))
                return
            }
            guard let tokenRequestString = obj["tokenRequest"] else {
                logger.error("Didn't receive a token request value in \(activity) response body: \(obj)")
                self.failureCallback("Having trouble with the whisper server.  Please try again later.")
                callback(nil, TcpAuthenticatorError.server("No token request in response"))
                return
            }
            guard let tokenRequest = try? ARTTokenRequest.fromJson(tokenRequestString as ARTJsonCompatible) else {
                logger.error("Can't deserialize token request JSON: \(tokenRequestString)")
                self.failureCallback("Having trouble with the whisper server.  Please try again later.")
                callback(nil, TcpAuthenticatorError.server("Token request is not expected format: \(tokenRequestString)"))
                return
            }
            logger.info("Received \(activity) token from whisper-server")
            callback(tokenRequest, nil)
        }
        logger.info("Posting \(activity) token request to whisper-server")
        task.resume()
    }
}
