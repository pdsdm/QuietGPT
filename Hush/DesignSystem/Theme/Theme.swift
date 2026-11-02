import SwiftUI

struct Palette {
    let background: Color
    let surface: Color
    let raised: Color
    let elevated: Color
    let line: Color
    let field: Color
    let text: Color
    let text2: Color
    let text3: Color
    let accent: Color
    let onAccent: Color
    let accentSoft: Color
    let accentText: Color
    let local: Color
    let localSoft: Color
    let danger: Color
    let primary: Color
    let onPrimary: Color

    static let dark = Palette(
        background: Color(hex: 0x000000),
        surface: Color(hex: 0x0E0E10),
        raised: Color(hex: 0x161618),
        elevated: Color(hex: 0x1F1F22),
        line: Color(hex: 0x2A2A2E),
        field: Color(hex: 0x3A3A41),
        text: Color(hex: 0xF4F4F1),
        text2: Color(hex: 0xA1A1A6),
        text3: Color(hex: 0x7C7C82),
        accent: Color(hex: 0x7CC4FF),
        onAccent: Color(hex: 0x04121F),
        accentSoft: Color(hex: 0x0D1B29),
        accentText: Color(hex: 0xA8D8FF),
        local: Color(hex: 0x7FD8AE),
        localSoft: Color(hex: 0x0F1F18),
        danger: Color(hex: 0xFF8A80),
        primary: Color(hex: 0xF4F4F1),
        onPrimary: Color(hex: 0x000000)
    )

    static let light = Palette(
        background: Color(hex: 0xF6F5F1),
        surface: Color(hex: 0xFFFFFF),
        raised: Color(hex: 0xECEBE6),
        elevated: Color(hex: 0xE4E3DD),
        line: Color(hex: 0xDCDAD3),
        field: Color(hex: 0xC9C7BE),
        text: Color(hex: 0x0A0A0A),
        text2: Color(hex: 0x5C5C60),
        text3: Color(hex: 0x6E6E73),
        accent: Color(hex: 0x1F7AE0),
        onAccent: Color(hex: 0xFFFFFF),
        accentSoft: Color(hex: 0xE3EFFC),
        accentText: Color(hex: 0x135BB0),
        local: Color(hex: 0x17784F),
        localSoft: Color(hex: 0xE3F2EA),
        danger: Color(hex: 0xC8372D),
        primary: Color(hex: 0x0A0A0A),
        onPrimary: Color(hex: 0xF6F5F1)
    )

    static func forScheme(_ scheme: ColorScheme) -> Palette {
        scheme == .light ? .light : .dark
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension EnvironmentValues {
    @Entry var palette: Palette = .dark
}

enum Appearance: String, CaseIterable, Identifiable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "Auto"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

enum HushFont {
    static let largeTitle = Font.system(.largeTitle, design: .default, weight: .regular)
    static let title = Font.system(.title2, design: .default, weight: .regular)
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

enum Motion {
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.8)
    static let gentle = Animation.spring(response: 0.6, dampingFraction: 0.9)
}
