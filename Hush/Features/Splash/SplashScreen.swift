import SwiftUI

struct SplashScreen: View {
    static let duration: Duration = .seconds(2.3)
    static let shortDuration: Duration = .seconds(0.6)

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine = BurstEngine()
    @State private var start = Date.now
    @State private var showsName = false

    private static let fontSize: CGFloat = 9
    private static let cellWidth: CGFloat = fontSize * 0.6
    private static let lineHeight: CGFloat = 9.5
    private static let side: CGFloat = 280

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: 24) {
                TimelineView(.animation(paused: reduceMotion)) { context in
                    Canvas { canvas, size in
                        let columns = Int(size.width / Self.cellWidth)
                        let rows = Int(size.height / Self.lineHeight)
                        let elapsed = reduceMotion ? 3 : context.date.timeIntervalSince(start)
                        let lines = engine.lines(
                            columns: columns,
                            rows: rows,
                            aspect: Double(Self.lineHeight / Self.cellWidth),
                            pose: BurstEngine.pose(at: elapsed)
                        )
                        let font = Font.system(size: Self.fontSize, weight: .medium, design: .monospaced)
                        for (row, line) in lines.enumerated() {
                            let text = canvas.resolve(Text(line).font(font).foregroundStyle(palette.text))
                            canvas.draw(text, at: CGPoint(x: size.width / 2, y: CGFloat(row) * Self.lineHeight), anchor: .top)
                        }
                    }
                }
                .frame(width: Self.side, height: Self.side)

                Wordmark(size: 30)
                    .opacity(showsName ? 1 : 0)
                    .offset(y: showsName ? 0 : 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BrandFont.name)
        .onAppear {
            start = .now
            withAnimation(.easeOut(duration: 0.5).delay(reduceMotion ? 0 : 0.9)) { showsName = true }
        }
    }
}

#Preview {
    SplashScreen()
}
