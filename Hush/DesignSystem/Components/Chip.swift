import SwiftUI

struct Chip: View {
    var title: String
    var dot: Color?

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            if let dot {
                LiveDot(color: dot)
            }
            Text(title)
                .font(HushFont.footnote)
        }
        .foregroundStyle(palette.text)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(palette.raised, in: .capsule)
    }
}
