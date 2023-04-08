// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

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
let (listenViewBottomPad, whisperViewBottomPad): (CGFloat, CGFloat) = {
    if ProcessInfo.processInfo.isiOSAppOnMac {
        return (20, 20)
    } else if UIDevice.current.userInterfaceIdiom == .phone {
        return (0, 5)
    } else {
        return (5, 15)
    }
}()

/// logging
import os
let logger = Logger()


@main
struct whisperApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}
