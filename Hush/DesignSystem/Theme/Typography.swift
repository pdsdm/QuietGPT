import SwiftUI

enum HushFont {
    static let largeTitle = BrandFont.font(.largeTitle)
    static let title = BrandFont.font(.title2)
    static let lead = BrandFont.font(.title3)
    static let headline = BrandFont.font(.headline, weight: .medium)
    static let body = BrandFont.font(.body)
    static let callout = BrandFont.font(.callout)
    static let subheadline = BrandFont.font(.subheadline)
    static let footnote = BrandFont.font(.footnote)
    static let caption = BrandFont.font(.caption2)
    static let mono = Font.system(.footnote, design: .monospaced, weight: .regular)
    static let monoSmall = Font.system(.caption, design: .monospaced, weight: .regular)

    static func wordmark(size: CGFloat) -> Font {
        BrandFont.wordmark(size: size)
    }
}
