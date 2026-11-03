import SwiftUI

struct Wordmark: View {
    var size: CGFloat = 28

    @Environment(\.palette) private var palette

    var body: some View {
        Text(BrandFont.name)
            .font(BrandFont.wordmark(size: size))
            .tracking(-size * 0.025)
            .foregroundStyle(palette.text)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel(BrandFont.name)
    }
}
