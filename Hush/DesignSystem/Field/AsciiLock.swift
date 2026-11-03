import SwiftUI

enum LockState: Equatable {
    case playing
    case open
    case locked
}

struct AsciiLock: View {
    var side: CGFloat = 280
    var state: LockState = .playing

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine = LockEngine()
    @State private var start = Date.now

    private let input = FieldInput.shared

    private static let fontSize: CGFloat = 9
    private static let cellWidth: CGFloat = fontSize * 0.6
    private static let lineHeight: CGFloat = 9.5

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            Canvas { canvas, size in
                let columns = Int(size.width / Self.cellWidth)
                let rows = Int(size.height / Self.lineHeight)
                let elapsed = context.date.timeIntervalSince(start)
                var pose = pose(at: elapsed)
                pose.yaw += input.tilt.x * 0.6
                pose.pitch = min(-0.04, pose.pitch + input.tilt.y * 0.3)
                let lines = engine.lines(
                    columns: columns,
                    rows: rows,
                    aspect: Double(Self.lineHeight / Self.cellWidth),
                    pose: pose
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
        .onAppear {
            start = .now
            input.start()
        }
        .onDisappear { input.stop() }
        .onChange(of: state) { start = .now }
    }

    private func pose(at elapsed: Double) -> LockEngine.Pose {
        if reduceMotion { return LockEngine.pose(at: state == .open ? 0 : LockEngine.settled) }
        switch state {
        case .playing:
            return LockEngine.pose(at: elapsed)
        case .open:
            var pose = LockEngine.pose(at: 0)
            pose.yaw += 0.12 * sin(elapsed * 1.4)
            pose.lift += 0.04 * sin(elapsed * 2.2)
            return pose
        case .locked:
            return LockEngine.pose(at: LockEngine.settled + elapsed)
        }
    }
}
