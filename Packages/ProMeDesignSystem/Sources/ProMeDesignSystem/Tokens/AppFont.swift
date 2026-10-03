import CoreText
import Foundation
import SwiftUI

/// App-wide typography based on the open-source Shabnam family bundled in
/// this package (github.com/rastikerdar/shabnam-font). The TTFs are
/// registered with CoreText once per process; on both macOS and iOS this
/// works identically, so no AppKit/UIKit dependency is needed.
public enum AppFont {
    public static let familyName = "Shabnam"

    private static let registration: Void = {
        let names = ["Shabnam", "Shabnam-Bold", "Shabnam-Medium", "Shabnam-Light"]
        for name in names {
            if let url = Bundle.module.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()

    public static func app(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        _ = registration
        return .custom(familyName, size: size(for: style), relativeTo: style).weight(weight)
    }

    private static func size(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 26
        case .title: 20
        case .title2: 17
        case .title3: 15
        case .headline: 13
        case .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote: 10
        case .caption: 10
        case .caption2: 9
        @unknown default: 13
        }
    }
}

public extension Font {
    /// The app typeface (Shabnam) in each text style.
    static var appLargeTitle: Font { AppFont.app(.largeTitle) }
    static var appTitle: Font { AppFont.app(.title) }
    static var appTitle2: Font { AppFont.app(.title2) }
    static var appTitle3: Font { AppFont.app(.title3) }
    static var appHeadline: Font { AppFont.app(.headline) }
    static var appBody: Font { AppFont.app(.body) }
    static var appCallout: Font { AppFont.app(.callout) }
    static var appSubheadline: Font { AppFont.app(.subheadline) }
    static var appFootnote: Font { AppFont.app(.footnote) }
    static var appCaption: Font { AppFont.app(.caption) }
    static var appCaption2: Font { AppFont.app(.caption2) }
}
