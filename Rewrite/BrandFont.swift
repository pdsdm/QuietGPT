import CoreText
import SwiftUI

enum BrandFont {
    static let name = "QuietGPT"

    private static let postScriptName: String? = {
        guard let url = Bundle.main.url(forResource: "Geist-SemiBold", withExtension: "ttf"),
              let provider = CGDataProvider(url: url as CFURL),
              let font = CGFont(provider) else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return font.postScriptName as String?
    }()

    static func wordmark(size: CGFloat) -> Font {
        guard let postScriptName else { return .system(size: size, weight: .semibold) }
        return .custom(postScriptName, fixedSize: size)
    }
}
