import SwiftUI

struct Wordmark: View {
    var size: CGFloat = 28
    var blinks = true

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: size * 0.06) {
            Text("hush")
                .font(HushFont.wordmark(size: size))
                .tracking(-size * 0.035)
            Capsule()
                .fill(palette.accent)
                .frame(width: max(2, size * 0.075), height: size * 0.72)
                .opacity(dim ? 0.25 : 1)
                .alignmentGuide(.lastTextBaseline) { $0[.bottom] - size * 0.02 }
        }
        .foregroundStyle(palette.text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("hush")
        .onAppear {
            guard blinks, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                dim = true
            }
        }
    }
}

struct AppMark: View {
    var size: CGFloat = 96
    var animated = false

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !animated || reduceMotion)) { context in
            Canvas { canvas, canvasSize in
                let rows = size >= 160 ? 18 : size >= 90 ? 14 : size >= 50 ? 10 : 7
                let tick = animated ? context.date.timeIntervalSinceReferenceDate * 12.5 : 0
                let lines = Self.rings(rows: rows, tick: tick)
                let fontSize = canvasSize.width / (CGFloat(rows * 2) * 0.6)
                let lineHeight = canvasSize.height / CGFloat(rows)
                let font = Font.system(size: fontSize, design: .monospaced)
                for (index, line) in lines.enumerated() {
                    let text = canvas.resolve(Text(line).font(font).foregroundStyle(palette.text3.opacity(0.8)))
                    canvas.draw(text, at: CGPoint(x: canvasSize.width / 2, y: (CGFloat(index) + 0.5) * lineHeight), anchor: .center)
                }
            }
        }
        .frame(width: size, height: size)
        .background(palette.background)
        .overlay {
            Capsule()
                .fill(palette.text)
                .frame(width: max(3, size * 0.075), height: size * 0.34)
        }
        .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(palette.line, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private static func rings(rows: Int, tick: Double) -> [String] {
        let columns = rows * 2
        let ramp: [Character] = Array(" .·:")
        let innerRadius = 0.3
        return (0..<rows).map { y in
            String((0..<columns).map { x in
                let nx = (Double(x) + 0.5) / Double(columns) * 2 - 1
                let ny = (Double(y) + 0.5) / Double(rows) * 2 - 1
                let distance = (nx * nx + ny * ny).squareRoot()
                guard distance >= innerRadius else { return " " }
                let ring = 0.5 + 0.5 * cos((distance - innerRadius) * .pi * 7 + tick * 0.2)
                let fade = max(0, 1 - (distance - innerRadius) / 0.85)
                return ramp[min(3, Int(ring * fade * 3.99))]
            })
        }
    }
}

struct LiveDot: View {
    var color: Color
    var size: CGFloat = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(color.opacity(0.35))
                    .scaleEffect(pulsing ? 2.6 : 1)
                    .opacity(pulsing ? 0 : 1)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            }
            .accessibilityHidden(true)
    }
}
