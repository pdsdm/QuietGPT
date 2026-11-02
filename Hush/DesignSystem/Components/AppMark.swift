import SwiftUI

struct AppMark: View {
    var size: CGFloat = 96
    var animated = false

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var visible: Bool { shown || !animated || reduceMotion }

    var body: some View {
        let unit = size / 100
        ZStack {
            palette.background
            LipLine()
                .trim(from: 0, to: visible ? 1 : 0)
                .stroke(palette.accent, style: StrokeStyle(lineWidth: 6 * unit, lineCap: .round))
            Capsule()
                .fill(palette.text)
                .frame(width: 7.5 * unit, height: 52 * unit)
                .position(x: 50 * unit, y: 48 * unit)
                .offset(y: visible ? 0 : 14 * unit)
                .opacity(visible ? 1 : 0)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(palette.line, lineWidth: 1)
        }
        .accessibilityHidden(true)
        .onAppear {
            guard animated, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.7).delay(0.2)) { shown = true }
        }
    }
}

struct LipLine: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / 100
        var path = Path()
        path.move(to: CGPoint(x: 27 * unit, y: 57 * unit))
        path.addQuadCurve(to: CGPoint(x: 73 * unit, y: 57 * unit), control: CGPoint(x: 50 * unit, y: 69 * unit))
        return path
    }
}
