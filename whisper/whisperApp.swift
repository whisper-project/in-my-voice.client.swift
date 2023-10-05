// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import AVFAudio
import SwiftUI

/// build information
#if targetEnvironment(simulator)
let platformInfo = "simulator"
#elseif targetEnvironment(macCatalyst)
let platformInfo = "mac"
#else
let platformInfo = UIDevice.current.userInterfaceIdiom == .phone ? "phone" : "pad"
#endif
let versionInfo = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "??"
let buildInfo = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "??"


/// global strings
let connectingLiveText = "This is where the line being typed by the whisperer will appear in real time... "
let connectingPastText = """
    This is where lines will move after the whisperer hits return.
    The most recent line will be on the bottom.
    """

/// global constants for light/dark mode
let lightLiveTextColor = Color(.black)
let darkLiveTextColor = Color(.white)
let lightLiveBorderColor = Color(.black)
let darkLiveBorderColor = Color(.white)
let lightPastTextColor = Color(.darkGray)
let darkPastTextColor = Color(.lightGray)
let lightPastBorderColor = Color(.darkGray)
let darkPastBorderColor = Color(.lightGray)

/// global constants for relative view sizes
let liveTextFifths = UIDevice.current.userInterfaceIdiom == .phone ? 2.0 : 1.0
let pastTextProportion = (5.0 - liveTextFifths)/5.0
let liveTextProportion = liveTextFifths/5.0

/// global constants for platform differentiation
#if targetEnvironment(macCatalyst)
    let sidePad = CGFloat(5)
    let innerPad = CGFloat(5)
    let listenViewTopPad = CGFloat(15)
    let whisperViewTopPad = CGFloat(15)
    let listenViewBottomPad = CGFloat(5)
    let whisperViewBottomPad = CGFloat(15)
#else   // iOS
    let sidePad = UIDevice.current.userInterfaceIdiom == .phone ? CGFloat(5) : CGFloat(10)
    let innerPad = UIDevice.current.userInterfaceIdiom == .phone ? CGFloat(5) : CGFloat(10)
    let listenViewTopPad = CGFloat(0)
    let whisperViewTopPad = CGFloat(0)
    let listenViewBottomPad = UIDevice.current.userInterfaceIdiom == .phone ? CGFloat(5) : CGFloat(5)
    let whisperViewBottomPad = UIDevice.current.userInterfaceIdiom == .phone ? CGFloat(5) : CGFloat(15)
#endif

/// global timeouts
let listenerAdTime = TimeInterval(2)    // seconds of listener advertising for whisperers
let listenerWaitTime = TimeInterval(3)  // seconds of listener wait for multiple whisperers to respond
let whispererAdTime = TimeInterval(2)   // seconds of whisperer advertising to listeners

/// logging
import os
let logger = Logger()


@main
struct whisperApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State var mode: OperatingMode = PreferenceData.initialMode()
    @State var publisherUrl: TransportUrl = nil
    @State var showWarning: Bool = false
    @State var warningMessage: String = ""

    var body: some Scene {
        WindowGroup {
            MainView(mode: $mode, publisherUrl: $publisherUrl)
                .onAppear { if (mode == .ask) { publisherUrl = nil } }
                .onOpenURL { urlObj in
                    let url = urlObj.absoluteString
                    if PreferenceData.publisherUrlToClientId(url: url) != nil {
                        logger.log("Handling valid universal URL: \(url)")
                        PreferenceData.lastSubscriberUrl = url
                        publisherUrl = url
                        mode = .listen
                    } else {
                        logger.warning("Ignoring invalid universal URL: \(url)")
                        warningMessage = "That is not a valid Whisper link"
                        showWarning = true
                    }
                }
                .alert("Cannot Listen", isPresented: $showWarning,
                       actions: { Button("OK", action: { })}, message: { Text(warningMessage) })
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        } catch (let err) {
            logger.error("Failed to set audio session category: \(err)")
        }
        logger.info("Registering for remote notifications")
        application.registerForRemoteNotifications()
        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        logger.info("Received APNs token")
        let value: [String: Any] = [
            "clientId": PreferenceData.clientId,
            "token": deviceToken.base64EncodedString(),
            "deviceId": BluetoothData.deviceId,
            "userName": PreferenceData.userName(),
            "lastSecret": PreferenceData.lastClientSecret(),
            "appInfo": "\(platformInfo)|\(versionInfo).\(buildInfo)",
            "droppedErrorCount": PreferenceData.droppedErrorCount,
            "tcpErrorCount": PreferenceData.tcpErrorCount,
            "authenticationErrorCount": PreferenceData.authenticationErrorCount,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: value) else {
            fatalError("Can't encode body for device token call")
        }
        guard let url = URL(string: PreferenceData.whisperServer + "/api/apnsToken") else {
            fatalError("Can't create URL for device token call")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            guard error == nil else {
                logger.error("Failed to post APNs token: \(String(describing: error))")
                return
            }
            guard let response = response as? HTTPURLResponse else {
                logger.error("Received non-HTTP response on APNs token post: \(String(describing: response))")
                return
            }
            if response.statusCode == 204 {
                logger.info("Successful post of APNs token")
                // if server has received error data, reset it
                PreferenceData.droppedErrorCount = 0
                PreferenceData.tcpErrorCount = 0
                PreferenceData.authenticationErrorCount = 0
                return
            }
            logger.error("Received unexpected response on APNs token post: \(response.statusCode)")
            guard let data = data,
                  let body = try? JSONSerialization.jsonObject(with: data),
                  let obj = body as? [String:String] else {
                logger.error("Can't deserialize APNs token post response body: \(String(describing: data))")
                return
            }
            logger.error("Response body of APNs token post: \(obj)")
        }
        logger.info("Posting APNs token to whisper-server")
        task.resume()
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("Failed to get APNs token: \(error)")
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        logger.info("Received APNs background notification")
        if let value = userInfo["secret"], let secret = value as? String {
            logger.info("Succesfully saved data from background notification")
            PreferenceData.updateClientSecret(secret)
            let value = [
                "clientId": PreferenceData.clientId,
                "lastSecret": PreferenceData.lastClientSecret()
            ]
            guard let body = try? JSONSerialization.data(withJSONObject: value) else {
                fatalError("Can't encode body for notification confirmation call")
            }
            guard let url = URL(string: PreferenceData.whisperServer + "/api/apnsReceivedNotification") else {
                fatalError("Can't create URL for notification confirmation call")
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                guard error == nil else {
                    fatalError("Failed to post notification confirmation: \(String(describing: error))")
                }
                guard let response = response as? HTTPURLResponse else {
                    fatalError("Received non-HTTP response on notification confirmation: \(String(describing: response))")
                }
                if response.statusCode == 204 {
                    logger.info("Successful post of notification confirmation")
                    completionHandler(.newData)
                    return
                }
                logger.error("Received unexpected response on notification confirmation post: \(response.statusCode)")
                completionHandler(.failed)
            }
            logger.info("Posting notification confirmation to whisper-server")
            task.resume()
        } else {
            logger.error("Background notification has unexpected data: \(String(describing: userInfo))")
            completionHandler(.failed)
        }
    }
}
