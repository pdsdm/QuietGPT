import SwiftUI

struct LipLine: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / 100
        var path = Path()
        path.move(to: CGPoint(x: 27 * unit, y: 57 * unit))
        path.addQuadCurve(to: CGPoint(x: 73 * unit, y: 57 * unit), control: CGPoint(x: 50 * unit, y: 69 * unit))
        return path
    }
}
