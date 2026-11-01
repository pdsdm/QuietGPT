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
