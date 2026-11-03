import SwiftUI

struct AsciiLock: View {
    var side: CGFloat = 280
    var startsLocked = false

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine = LockEngine()
    @State private var start = Date.now

    private static let fontSize: CGFloat = 9
    private static let cellWidth: CGFloat = fontSize * 0.6
    private static let lineHeight: CGFloat = 9.5

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            Canvas { canvas, size in
                let columns = Int(size.width / Self.cellWidth)
                let rows = Int(size.height / Self.lineHeight)
                let offset = startsLocked || reduceMotion ? LockEngine.settled : 0
                let lines = engine.lines(
                    columns: columns,
                    rows: rows,
                    aspect: Double(Self.lineHeight / Self.cellWidth),
                    pose: LockEngine.pose(at: offset + context.date.timeIntervalSince(start))
                )
                let font = Font.system(size: Self.fontSize, weight: .medium, design: .monospaced)
                for (row, line) in lines.enumerated() {
                    let text = canvas.resolve(Text(line).font(font).foregroundStyle(palette.text))
                    canvas.draw(text, at: CGPoint(x: size.width / 2, y: CGFloat(row) * Self.lineHeight), anchor: .top)
                }
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
        .onAppear { start = .now }
    }
}
