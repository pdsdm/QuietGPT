import SwiftUI

struct Burst: Shape {
    static let rays = 8
    static let inner: CGFloat = 23 / 120
    static let outer: CGFloat = 49 / 120
    static let weight: CGFloat = 10 / 120

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for ray in 0..<Self.rays {
            let angle = -Double.pi / 2 + Double(ray) * 2 * .pi / Double(Self.rays)
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            path.move(to: CGPoint(x: center.x + direction.x * Self.inner * side, y: center.y + direction.y * Self.inner * side))
            path.addLine(to: CGPoint(x: center.x + direction.x * Self.outer * side, y: center.y + direction.y * Self.outer * side))
        }
        return path
    }

    static func stroke(size: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: size * weight, lineCap: .round)
    }
}
