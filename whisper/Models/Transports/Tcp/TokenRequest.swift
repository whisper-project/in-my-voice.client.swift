// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation
import SwiftJWT

struct ClientClaims: Claims {
    let iss: String
    let exp: Date
}

func createJWT() -> String? {
    guard let secret = PreferenceData.clientSecret(),
          let secretData = Data(base64Encoded: Data(secret.utf8)) else {
        logger.error("No secret data received from whisper-server")
        return nil
    }
    let claims = ClientClaims(iss: PreferenceData.clientId, exp: Date(timeIntervalSinceNow: 3600))
    var jwt = JWT(claims: claims)
    let signer = JWTSigner.hs256(key: secretData)
    let signedJWT = try? jwt.sign(using: signer)
    return signedJWT
}

func getTokenRequest(mode: OperatingMode, publisherId: String, callback: @escaping (String?) -> ()) {
    guard let jwt = createJWT() else {
        logger.error("Couldn't create JWT to post token request")
        callback(nil)
        return
    }
    let activity = mode == .whisper ? "publish" : "subscribe"
    let value = [
        "clientId": PreferenceData.clientId,
        "activity": mode == .whisper ? "publish" : "subscribe",
        "publisherId": publisherId
    ]
    guard let body = try? JSONSerialization.data(withJSONObject: value) else {
        fatalError("Can't encode body for \(activity) token request call")
    }
    guard let url = URL(string: PreferenceData.whisperServer + "/pubSubTokenRequest") else {
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
            callback(nil)
            return
        }
        guard let response = response as? HTTPURLResponse else {
            logger.error("Received non-HTTP response on \(activity) token request: \(String(describing: response))")
            callback(nil)
            return
        }
        if response.statusCode != 200 {
            logger.warning("Received unexpected response status on \(activity) token request: \(response.statusCode)")
        }
        guard let data = data,
              let body = try? JSONSerialization.jsonObject(with: data),
              let obj = body as? [String:String] else {
            logger.error("Can't deserialize \(activity) token response body: \(String(describing: data))")
            callback(nil)
            return
        }
        guard let tokenRequest = obj["tokenRequest"] else {
            logger.error("Didn't receive a token request value in \(activity) response body: \(obj)")
            callback(nil)
            return
        }
        logger.info("Received \(activity) token from whisper-server")
        callback(tokenRequest)
    }
    logger.info("Posting \(activity) token request to whisper-server")
    task.resume()
}
