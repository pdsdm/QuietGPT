import SwiftUI
import UIKit

struct AssistantBox<Content: View>: View {
    @ViewBuilder var content: Content

    @Environment(\.palette) private var palette

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 6, bottomTrailingRadius: 22, topTrailingRadius: 22, style: .continuous)
    }

    var body: some View {
        HStack {
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(palette.surface, in: shape)
                .overlay { shape.strokeBorder(palette.line, lineWidth: 1) }
            Spacer(minLength: 28)
        }
    }
}

struct AssistantMessage: View {
    let text: String
    var isLatest = false
    var onRegenerate: (() -> Void)?

    @Environment(\.palette) private var palette
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AssistantBox {
                MarkdownView(text: text)
            }
            HStack(spacing: 4) {
                Button {
                    UIPasteboard.general.string = text
                    withAnimation(Motion.snappy) { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        withAnimation(Motion.snappy) { copied = false }
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "square.on.square")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 36, height: 32)
                }
                .accessibilityLabel(copied ? "Copied" : "Copy")
                .sensoryFeedback(.success, trigger: copied) { _, new in new }

                if isLatest, let onRegenerate {
                    Button(action: onRegenerate) {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 36, height: 32)
                    }
                    .accessibilityLabel("Try again")
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(palette.text3)
            .buttonStyle(PressableStyle(scale: 0.85))
            .padding(.leading, 4)
        }
    }
}
