import SwiftUI

struct AppMark: View {
    var size: CGFloat = 96
    var animated = false

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var visible: Bool { shown || !animated || reduceMotion }

    var body: some View {
        let mark = size * 0.6
        ZStack {
            palette.background
            Burst()
                .trim(from: 0, to: visible ? 1 : 0)
                .stroke(palette.text, style: Burst.stroke(size: mark))
                .frame(width: mark, height: mark)
                .rotationEffect(.degrees(visible ? 0 : -45))
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
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) { shown = true }
        }
    }
}
