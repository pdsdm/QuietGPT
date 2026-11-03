import CoreText
import SwiftUI

enum BrandFont {
    static let name = "QuietGPT"

    private static let files: [Font.Weight: String] = [
        .light: "Geist-Light",
        .regular: "Geist-Regular",
        .medium: "Geist-Medium",
        .semibold: "Geist-SemiBold",
    ]

    private static let postScriptNames: [Font.Weight: String] = {
        var names: [Font.Weight: String] = [:]
        for (weight, file) in files {
            guard let url = Bundle.main.url(forResource: file, withExtension: "ttf"),
                  let provider = CGDataProvider(url: url as CFURL),
                  let font = CGFont(provider),
                  let postScriptName = font.postScriptName as String? else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            names[weight] = postScriptName
        }
        return names
    }()

    private static func face(_ weight: Font.Weight) -> Font.Weight {
        switch weight {
        case .ultraLight, .thin, .light: .light
        case .medium: .medium
        case .semibold, .bold, .heavy, .black: .semibold
        default: .regular
        }
    }

    static func wordmark(size: CGFloat) -> Font {
        guard let postScriptName = postScriptNames[.semibold] else { return .system(size: size, weight: .semibold) }
        return .custom(postScriptName, fixedSize: size)
    }

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard let postScriptName = postScriptNames[face(weight)] else { return .system(size: size, weight: weight) }
        return .custom(postScriptName, fixedSize: size)
    }

    static func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        guard let postScriptName = postScriptNames[face(weight)] else { return .system(style, weight: weight) }
        return .custom(postScriptName, size: pointSize(style), relativeTo: style)
    }

    static func uiFont(size: CGFloat, weight: Font.Weight = .regular) -> UIFont? {
        postScriptNames[face(weight)].flatMap { UIFont(name: $0, size: size) }
    }

    private static func pointSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline: 17
        case .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }
}
