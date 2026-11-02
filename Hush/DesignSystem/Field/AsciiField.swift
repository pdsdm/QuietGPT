import SwiftUI

enum FieldMask {
    case none
    case fadeDown
    case fadeUp
    case vignette
}

struct AsciiField: View {
    var mode: FieldMode = .drift
    var mask: FieldMask = .vignette

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine = FieldEngine()

    private static let fontSize: CGFloat = 11
    private static let cellWidth: CGFloat = fontSize * 0.6
    private static let lineHeight: CGFloat = 13

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: reduceMotion)) { context in
            Canvas(rendersAsynchronously: true) { canvas, size in
                let grid = FieldEngine.Grid(
                    columns: Int((size.width / Self.cellWidth).rounded(.up)) + 1,
                    rows: Int((size.height / Self.lineHeight).rounded(.up)) + 1
                )
                let lines = engine.lines(for: grid, at: context.date, mode: mode)
                let font = Font.system(size: Self.fontSize, design: .monospaced)
                for (row, line) in lines.enumerated() {
                    let text = canvas.resolve(Text(line).font(font).foregroundStyle(palette.field))
                    canvas.draw(text, at: CGPoint(x: size.width / 2, y: CGFloat(row) * Self.lineHeight), anchor: .top)
                }
            }
        }
        .mask(maskShape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var frameInterval: TimeInterval {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? 1.0 / 15 : 1.0 / 24
    }

    @ViewBuilder
    private var maskShape: some View {
        switch mask {
        case .none:
            Rectangle()
        case .fadeDown:
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.35), .init(color: .clear, location: 0.95)], startPoint: .top, endPoint: .bottom)
        case .fadeUp:
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.3), .init(color: .clear, location: 0.9)], startPoint: .bottom, endPoint: .top)
        case .vignette:
            EllipticalGradient(stops: [.init(color: .black, location: 0.3), .init(color: .clear, location: 0.8)])
        }
    }
}

#Preview {
    AsciiField(mode: .drift)
        .background(.black)
        .ignoresSafeArea()
}
