// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import AVFAudio
import SwiftUI

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
let pastTextProportion = 4.0/5.0
let liveTextProportion = 1.0/5.0

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
let listenerWaitTime = TimeInterval(4)  // seconds of listener wait for multiple whisperers to respond
let whispererAdTime = TimeInterval(2)   // seconds of whisperer advertising to listeners

/// logging
import os
let logger = Logger()


@main
struct whisperApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainView()
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
        let value = [
            "clientId": PreferenceData.clientId,
            "apnsToken": deviceToken.base64EncodedString(),
            "deviceId": BluetoothData.deviceId,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: value) else {
            fatalError("Can't encode body for device token call")
        }
        guard let url = URL(string: "https://whisper-server-stage-baa911f67e80.herokuapp.com/apnsToken") else {
            fatalError("Can't create URL for device token call")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            guard error == nil else {
                fatalError("Failed to post APNs token: \(String(describing: error))")
            }
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                fatalError("Received error status on APNs token post: \(String(describing: response))")
            }
            guard let data = data,
                  let body = try? JSONSerialization.jsonObject(with: data),
                  let obj = body as? [String:String] else {
                fatalError("Can't deserialize JSON body: \(String(describing: data))")
            }
            logger.info("Successful post of APNs token: \(obj)")
        }
        logger.info("Posting APNs token to whisper-server")
        task.resume()
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("Failed to get APNs token: \(error)")
    }
}
