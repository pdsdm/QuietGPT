import SwiftUI
import UIKit

enum AsciiGlyphs {
    static let ramp: [Character] = Array(" .:-=+*o#%@")
    static let cell = CGSize(width: 4.8, height: 8)
    static let fontSize: CGFloat = 8
    static let weight: UIFont.Weight = .medium

    static let atlas: Image = {
        let count = ramp.count
        let format = UIGraphicsImageRendererFormat()
        format.scale = 4
        format.opaque = false
        let size = CGSize(width: cell.width * CGFloat(count), height: cell.height)
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            for (index, character) in ramp.enumerated() {
                let text = String(character) as NSString
                let bounds = text.size(withAttributes: attributes)
                let origin = CGPoint(
                    x: CGFloat(index) * cell.width + (cell.width - bounds.width) / 2,
                    y: (cell.height - bounds.height) / 2
                )
                text.draw(at: origin, withAttributes: attributes)
            }
        }
        return Image(uiImage: image)
    }()
}
