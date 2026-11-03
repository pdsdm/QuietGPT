import SwiftUI

enum HushFont {
    static let largeTitle = Font.system(.largeTitle, design: .default, weight: .regular)
    static let title = Font.system(.title2, design: .default, weight: .regular)
    static let lead = Font.system(.title3, design: .default, weight: .regular)
    static let headline = Font.system(.headline, design: .default, weight: .medium)
    static let body = Font.system(.body, design: .default, weight: .regular)
    static let callout = Font.system(.callout, design: .default, weight: .regular)
    static let subheadline = Font.system(.subheadline, design: .default, weight: .regular)
    static let footnote = Font.system(.footnote, design: .default, weight: .regular)
    static let caption = Font.system(.caption2, design: .default, weight: .regular)
    static let mono = Font.system(.footnote, design: .monospaced, weight: .regular)
    static let monoSmall = Font.system(.caption, design: .monospaced, weight: .regular)

    static func wordmark(size: CGFloat) -> Font {
        .system(size: size, weight: .light, design: .default)
    }
}
