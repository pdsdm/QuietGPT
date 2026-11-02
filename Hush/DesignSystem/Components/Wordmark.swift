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
