import SwiftUI

struct ThoughtBox: View {
    let text: String
    let isLive: Bool
    @Binding var expanded: Bool

    @Environment(\.palette) private var palette
    @State private var textHeight: CGFloat = 0

    private let previewHeight: CGFloat = 84

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(Motion.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                    Text(isLive ? "Thinking" : "Thought")
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(QuietGPTFont.caption)
                .foregroundStyle(palette.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Hide thought" : "Show thought")

            if expanded {
                thoughtText(text)
                    .textSelection(.enabled)
                    .transition(.opacity)
            } else if isLive, !text.isEmpty {
                thoughtText(text)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
                    .frame(maxHeight: previewHeight, alignment: .bottom)
                    .clipped()
                    .mask {
                        LinearGradient(stops: [.init(color: textHeight > previewHeight ? .clear : .black, location: 0), .init(color: .black, location: 0.35)], startPoint: .top, endPoint: .bottom)
                    }
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.elevated.opacity(0.6), in: .rect(cornerRadius: 12, style: .continuous))
    }

    private func thoughtText(_ text: String) -> some View {
        Text(text)
            .font(QuietGPTFont.footnote)
            .foregroundStyle(palette.text3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
