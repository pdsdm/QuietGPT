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
    let toggle: Color

    static let dark = Palette(
        background: Color(hex: 0x000000),
        surface: Color(hex: 0x0E0E0E),
        raised: Color(hex: 0x161616),
        elevated: Color(hex: 0x1F1F1F),
        line: Color(hex: 0x2A2A2A),
        field: Color(hex: 0x3A3A3A),
        text: Color(hex: 0xFFFFFF),
        text2: Color(hex: 0xA3A3A3),
        text3: Color(hex: 0x7D7D7D),
        accent: Color(hex: 0xFFFFFF),
        onAccent: Color(hex: 0x0A0A0A),
        accentSoft: Color(hex: 0x1A1A1A),
        accentText: Color(hex: 0xFFFFFF),
        local: Color(hex: 0xFFFFFF),
        localSoft: Color(hex: 0x1A1A1A),
        danger: Color(hex: 0xFF8A80),
        primary: Color(hex: 0xFFFFFF),
        onPrimary: Color(hex: 0x0A0A0A),
        toggle: Color(hex: 0x0A84FF)
    )

    static let light = Palette(
        background: Color(hex: 0xFFFFFF),
        surface: Color(hex: 0xF7F7F7),
        raised: Color(hex: 0xEFEFEF),
        elevated: Color(hex: 0xE7E7E7),
        line: Color(hex: 0xE2E2E2),
        field: Color(hex: 0xCFCFCF),
        text: Color(hex: 0x0A0A0A),
        text2: Color(hex: 0x5C5C5C),
        text3: Color(hex: 0x6E6E6E),
        accent: Color(hex: 0x0A0A0A),
        onAccent: Color(hex: 0xFFFFFF),
        accentSoft: Color(hex: 0xEFEFEF),
        accentText: Color(hex: 0x0A0A0A),
        local: Color(hex: 0x0A0A0A),
        localSoft: Color(hex: 0xEFEFEF),
        danger: Color(hex: 0xC8372D),
        primary: Color(hex: 0x0A0A0A),
        onPrimary: Color(hex: 0xFFFFFF),
        toggle: Color(hex: 0x0A0A0A)
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
