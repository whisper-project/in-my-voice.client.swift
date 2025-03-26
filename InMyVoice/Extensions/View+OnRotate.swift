// Copyright 2024 by Paul Hudson
//
// The code in this file is licensed under Paul Hudson's MIT non-AI license,
// as found at this link: https://www.hackingwithswift.com/license

import Foundation
import SwiftUI

struct DeviceRotationViewModifier: ViewModifier {
	let action: (UIDeviceOrientation) -> Void

	func body(content: Content) -> some View {
		content
			.onAppear()
			.onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
				action(UIDevice.current.orientation)
			}
	}
}

// A View wrapper to make the modifier easier to use
extension View {
	func onRotate(perform action: @escaping (UIDeviceOrientation) -> Void) -> some View {
		self.modifier(DeviceRotationViewModifier(action: action))
	}
}
