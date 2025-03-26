// Copyright 2023 Daniel C Brotsky.  All rights reserved.
//
// All material in this project and repository is licensed under the
// GNU Affero General Public License v3. See the LICENSE file for details.

import SwiftUI

struct FontSizes {
    static let fontSizeMap: [Font] = [
        Font.caption2,
        Font.caption,
        Font.subheadline,
        Font.callout,
        Font.body,
        Font.title3,
        Font.title2,
        Font.title,
        Font.largeTitle,
    ]
    
    typealias FontSize = Int
    
    enum FontName: Int {
        case xxxsmall = 0
        case xxsmall = 1
        case xsmall = 2
        case small = 3
        case normal = 4
        case large = 5
        case xlarge = 6
        case xxlarge = 7
        case xxxlarge = 8
    }
    
    static func fontFor(name: FontName) -> Font {
        return fontSizeMap[name.rawValue]
    }
    
    static func fontFor(_ size: Int) -> Font {
        if 0 <= size && size < fontSizeMap.count {
            return fontSizeMap[size]
        } else {
            return fontFor(name: .normal)
        }
    }
    
	static let minTextSize = platformInfo == "mac" ? 5 : 4
    static let maxTextSize = 8

    static func nextTextLarger(_ size: Int) -> Int {
        guard size < maxTextSize else {
            return maxTextSize
        }
        return size + 1
    }
    
    static func nextTextSmaller(_ size: Int) -> Int {
        guard size > minTextSize else {
            return minTextSize
        }
        return size - 1
    }
}
