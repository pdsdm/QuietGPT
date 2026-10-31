import SwiftUI

struct KeyStyle {
    let key: Color
    let special: Color
    let shadow: Color
    let text: Color
    let secondary: Color
    let selected: Color
    let onSelected: Color
    let accent: Color

    static func current(_ scheme: ColorScheme) -> KeyStyle {
        scheme == .dark ? dark : light
    }

    static let light = KeyStyle(
        key: Color(red: 1, green: 1, blue: 1),
        special: Color(red: 171 / 255, green: 176 / 255, blue: 186 / 255),
        shadow: Color(red: 137 / 255, green: 138 / 255, blue: 141 / 255),
        text: Color(red: 0, green: 0, blue: 0),
        secondary: Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255),
        selected: Color(red: 0, green: 0, blue: 0),
        onSelected: Color(red: 1, green: 1, blue: 1),
        accent: Color(red: 91 / 255, green: 84 / 255, blue: 232 / 255)
    )

    static let dark = KeyStyle(
        key: Color(red: 107 / 255, green: 107 / 255, blue: 107 / 255),
        special: Color(red: 70 / 255, green: 70 / 255, blue: 70 / 255),
        shadow: Color(red: 0, green: 0, blue: 0),
        text: Color(red: 1, green: 1, blue: 1),
        secondary: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.7),
        selected: Color(red: 1, green: 1, blue: 1),
        onSelected: Color(red: 0, green: 0, blue: 0),
        accent: Color(red: 169 / 255, green: 164 / 255, blue: 255 / 255)
    )
}

struct KeyFace: View {
    let color: Color
    let shadow: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color)
            .shadow(color: shadow, radius: 0, x: 0, y: 1)
    }
}
