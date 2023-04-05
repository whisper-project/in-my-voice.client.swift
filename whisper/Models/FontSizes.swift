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
        Font.headline,
        Font.title3,
        Font.title2,
        Font.title,
        Font.largeTitle,
    ]
    
    enum FontSize: Int {
        case xxxsmall = 0
        case xxsmall = 1
        case xsmall = 2
        case small = 3
        case normal = 4
        case large = 5
        case xlarge = 6
        case xxlarge = 7
        case xxxlarge = 8
        case xxxxlarge = 9
    }
    
    static let minSize = 0
    static let maxSize = 9
    
    static func fontFor(_ size: FontSize) -> Font {
        return fontSizeMap[size.rawValue]
    }
    
    static func nextLarger(_ size: FontSize) -> FontSize {
        guard size.rawValue < maxSize else {
            return FontSize.xxxxlarge
        }
        return FontSize(rawValue: size.rawValue + 1)!
    }
    
    static func nextSmaller(_ size: FontSize) -> FontSize {
        guard size.rawValue > FontSize.normal.rawValue else {
            return FontSize.normal
        }
        return FontSize(rawValue: size.rawValue - 1)!
    }
}
