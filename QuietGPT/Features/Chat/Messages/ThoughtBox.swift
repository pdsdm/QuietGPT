import SwiftUI

struct ThoughtBox: View {
    let text: String
    let isLive: Bool

    @Environment(\.palette) private var palette
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(Motion.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                    Text(isLive ? "Thinking" : "Thought")
                    if !isLive {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .font(QuietGPTFont.caption)
                .foregroundStyle(palette.text3)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isLive)
            .accessibilityLabel(isLive ? "Thinking" : expanded ? "Hide thought" : "Show thought")

            if isLive {
                ScrollView {
                    Text(text)
                        .font(QuietGPTFont.footnote)
                        .foregroundStyle(palette.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 84)
                .scrollDisabled(true)
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.bottom)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
                .mask {
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.35)], startPoint: .top, endPoint: .bottom)
                }
                .transition(.opacity)
            } else if expanded {
                Text(text)
                    .font(QuietGPTFont.footnote)
                    .foregroundStyle(palette.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.elevated.opacity(0.6), in: .rect(cornerRadius: 12, style: .continuous))
    }
}
