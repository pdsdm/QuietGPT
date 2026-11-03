import SwiftUI
import UIKit

struct KeyStyle {
    let background: UIColor
    let key: UIColor
    let pressed: UIColor
    let lit: UIColor
    let popup: UIColor
    let outline: UIColor
    let text: UIColor
    let secondary: UIColor
    let tag: UIColor
    let separator: UIColor
    let accent: UIColor

    static func current(_ scheme: ColorScheme) -> KeyStyle {
        scheme == .dark ? dark : light
    }

    static func current(_ traits: UITraitCollection) -> KeyStyle {
        traits.userInterfaceStyle == .dark ? dark : light
    }

    static let blue = UIColor(red: 0, green: 122 / 255, blue: 1, alpha: 1)
    static let radius: CGFloat = 8.5

    static let light = KeyStyle(
        background: UIColor(red: 224 / 255, green: 225 / 255, blue: 226 / 255, alpha: 1),
        key: UIColor(white: 1, alpha: 1),
        pressed: UIColor(red: 232 / 255, green: 232 / 255, blue: 236 / 255, alpha: 1),
        lit: UIColor(red: 214 / 255, green: 215 / 255, blue: 219 / 255, alpha: 1),
        popup: UIColor(white: 1, alpha: 1),
        outline: UIColor(white: 0, alpha: 0.08),
        text: UIColor(white: 0, alpha: 1),
        secondary: UIColor(red: 60 / 255, green: 60 / 255, blue: 67 / 255, alpha: 0.75),
        tag: UIColor(red: 175 / 255, green: 176 / 255, blue: 175 / 255, alpha: 1),
        separator: UIColor(red: 209 / 255, green: 210 / 255, blue: 212 / 255, alpha: 1),
        accent: UIColor(red: 31 / 255, green: 122 / 255, blue: 224 / 255, alpha: 1)
    )

    static let dark = KeyStyle(
        background: UIColor(white: 23 / 255, alpha: 1),
        key: UIColor(white: 117 / 255, alpha: 1),
        pressed: UIColor(red: 42 / 255, green: 44 / 255, blue: 42 / 255, alpha: 1),
        lit: UIColor(white: 165 / 255, alpha: 1),
        popup: UIColor(white: 140 / 255, alpha: 1),
        outline: UIColor(white: 1, alpha: 0.14),
        text: UIColor(white: 1, alpha: 1),
        secondary: UIColor(red: 235 / 255, green: 235 / 255, blue: 245 / 255, alpha: 0.7),
        tag: UIColor(red: 142 / 255, green: 142 / 255, blue: 147 / 255, alpha: 1),
        separator: UIColor(red: 43 / 255, green: 43 / 255, blue: 45 / 255, alpha: 1),
        accent: UIColor(red: 124 / 255, green: 196 / 255, blue: 1, alpha: 1)
    )
}
