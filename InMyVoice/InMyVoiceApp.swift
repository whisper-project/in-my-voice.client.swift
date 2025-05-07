// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import AVFAudio
import SwiftUI
import UserNotifications

/// build information
#if targetEnvironment(macCatalyst)
let platformInfo = "mac"
#else
let platformInfo = UIDevice.current.userInterfaceIdiom == .phone ? "phone" : "pad"
#endif
let versionInfo = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "??"
let buildInfo = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "??"
let versionString = buildInfo

/// global strings and URLs
let connectingLiveText = "This is where the line being typed by the whisperer will appear in real time... "
let connectingPastText = """
    This is where lines will move after the whisperer hits return.
    The most recent line will be on the bottom.
    """
let settingsUrl = URL(string: UIApplication.openSettingsURLString)!

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
let listenerWaitTime = TimeInterval(2)  // seconds of Bluetooth listener search before checking the internet
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
			logger.error("Failed to set audio session category: \(err, privacy: .public)")
        }
		PreferenceData.syncProfile()
		ServerProtocol.notifyLaunch()
		ElevenLabs.shared.notifyUsage()
		ElevenLabs.shared.downloadSettings()
		FavoritesProfile.shared.downloadFavorites()
        return true
    }
    
	func applicationWillTerminate(_ application: UIApplication) {
		ServerProtocol.notifyQuit()
	}
}
