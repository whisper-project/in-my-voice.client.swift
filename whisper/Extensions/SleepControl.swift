// Copyright 2024 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import Foundation

#if targetEnvironment(macCatalyst)
import IOKit.pwr_mgt

final class SleepControl {
	static var shared: SleepControl = .init()

	private var assertionID: IOPMAssertionID = 0
	private var sleepDisabled = false

	func disable(reason: String) {
		logger.info("Disabling sleep: \(reason, privacy: .public)")
		if !sleepDisabled {
			let status = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &assertionID)
			if status == kIOReturnSuccess {
				sleepDisabled = true
			} else {
				logAnomaly("Couldn't disable auto-screen-sleep on Mac: return value was \(status)")
			}
		}
	}

	func enable() {
		logger.info("Enabling sleep")
		if sleepDisabled {
			IOPMAssertionRelease(assertionID)
			sleepDisabled = false
		}
	}
}
#else
import UIKit

final class SleepControl {
	static var shared: SleepControl = .init()

	func disable(reason: String) {
		UIApplication.shared.isIdleTimerDisabled = true
	}

	func enable() {
		UIApplication.shared.isIdleTimerDisabled = false
	}
}
#endif

