import SwiftUI
import UIKit

struct KeyStyle {
    let key: Color
    let pressed: Color
    let popup: Color
    let line: Color
    let text: Color
    let secondary: Color
    let tag: Color
    let selected: Color
    let onSelected: Color
    let accent: Color

    static func current(_ scheme: ColorScheme) -> KeyStyle {
        scheme == .dark ? dark : light
    }

    static let blue = Color(uiColor: .systemBlue)

    static let light = KeyStyle(
        key: Color(red: 1, green: 1, blue: 1),
        pressed: Color(red: 232 / 255, green: 232 / 255, blue: 236 / 255),
        popup: Color(red: 1, green: 1, blue: 1),
        line: Color(red: 0, green: 0, blue: 0).opacity(0.12),
        text: Color(red: 0, green: 0, blue: 0),
        secondary: Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.75),
        tag: Color(red: 175 / 255, green: 176 / 255, blue: 175 / 255),
        selected: Color(red: 0, green: 0, blue: 0),
        onSelected: Color(red: 1, green: 1, blue: 1),
        accent: Color(red: 91 / 255, green: 84 / 255, blue: 232 / 255)
    )

    static let dark = KeyStyle(
        key: Color(red: 60 / 255, green: 61 / 255, blue: 60 / 255),
        pressed: Color(red: 42 / 255, green: 44 / 255, blue: 42 / 255),
        popup: Color(red: 86 / 255, green: 87 / 255, blue: 86 / 255),
        line: Color(red: 1, green: 1, blue: 1).opacity(0.12),
        text: Color(red: 1, green: 1, blue: 1),
        secondary: Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.7),
        tag: Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255),
        selected: Color(red: 1, green: 1, blue: 1),
        onSelected: Color(red: 0, green: 0, blue: 0),
        accent: Color(red: 169 / 255, green: 164 / 255, blue: 255 / 255)
    )
}

extension EdgeInsets {
    static func key(leading: CGFloat = 0, trailing: CGFloat = 0) -> EdgeInsets {
        EdgeInsets(top: 5.5, leading: 3 + leading, bottom: 5.5, trailing: 3 + trailing)
    }
}

struct KeyFace: View {
    static let radius: CGFloat = 8.5

    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
            .fill(color)
    }
}
