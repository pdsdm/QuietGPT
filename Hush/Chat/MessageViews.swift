import SwiftUI
import UIKit

struct UserBubble: View {
    let text: String

    @Environment(\.palette) private var palette

    var body: some View {
        HStack {
            Spacer(minLength: 56)
            Text(text)
                .font(HushFont.body)
                .foregroundStyle(palette.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(palette.elevated, in: UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22, bottomTrailingRadius: 6, topTrailingRadius: 22, style: .continuous))
                .textSelection(.enabled)
        }
    }
}

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

struct StreamingMessage: View {
    let text: String
    let isThinking: Bool

    @Environment(\.palette) private var palette
    @State private var arrivals: [StreamArrival] = []
    @State private var seen = 0

    var body: some View {
        AssistantBox {
            if isThinking && text.isEmpty {
                ThinkingGlyphs()
                    .transition(.blurReplace)
            } else {
                content
                    .transition(.blurReplace)
            }
        }
        .animation(Motion.spring, value: isThinking && text.isEmpty)
        .onChange(of: text, initial: true) { _, newValue in
            if newValue.count < seen {
                arrivals.removeAll()
            }
            if newValue.count > seen {
                arrivals.append(StreamArrival(offset: min(seen, newValue.count), time: Date.now.timeIntervalSinceReferenceDate))
                arrivals.removeAll { Date.now.timeIntervalSinceReferenceDate - $0.time > 2 }
            }
            seen = newValue.count
        }
    }

    @ViewBuilder
    private var content: some View {
        let blocks = MarkdownBlocks.parse(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                if block.id == blocks.last?.id {
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        StreamingText(
                            text: block.text,
                            arrivals: arrivals,
                            offset: block.start,
                            font: block.isCode ? HushFont.mono : HushFont.body,
                            color: palette.text
                        )
                        StreamCursor()
                    }
                    .modifier(BlockChrome(kind: block.kind))
                } else {
                    MarkdownBlockView(block: block)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MarkdownBlocks.parse(text)) { block in
                MarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock

    @Environment(\.palette) private var palette

    var body: some View {
        switch block.kind {
        case .code(let language):
            CodeBlock(code: block.text, language: language)
        case .heading:
            Text(styled(block.text))
                .font(HushFont.title)
                .foregroundStyle(palette.text)
        case .bullet, .numbered, .paragraph:
            Text(styled(block.text))
                .font(HushFont.body)
                .foregroundStyle(palette.text)
                .modifier(BlockChrome(kind: block.kind))
        }
    }

    private func styled(_ text: String) -> AttributedString {
        var string = AttributedString.inlineMarkdown(text)
        for run in string.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            if intent.contains(.stronglyEmphasized) {
                string[run.range].inlinePresentationIntent = intent.subtracting(.stronglyEmphasized)
                string[run.range].font = .system(.body, weight: .medium)
            }
            if intent.contains(.code) {
                string[run.range].font = .system(.callout, design: .monospaced)
                string[run.range].backgroundColor = palette.raised
            }
        }
        return string
    }
}

private struct BlockChrome: ViewModifier {
    let kind: MarkdownBlock.Kind

    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        switch kind {
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("·")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(palette.accent)
                content
            }
        case .numbered(let number):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(number)
                    .font(HushFont.mono)
                    .foregroundStyle(palette.text3)
                content
            }
        case .code:
            content
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.background, in: .rect(cornerRadius: 14, style: .continuous))
        case .paragraph, .heading:
            content
        }
    }
}

struct CodeBlock: View {
    let code: String
    let language: String

    @Environment(\.palette) private var palette
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    withAnimation(Motion.snappy) { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        withAnimation(Motion.snappy) { copied = false }
                    }
                } label: {
                    Text(copied ? "copied" : "copy")
                        .contentTransition(.numericText())
                        .frame(minHeight: 32)
                }
                .buttonStyle(PressableStyle())
            }
            .font(HushFont.monoSmall)
            .foregroundStyle(palette.text3)
            .padding(.horizontal, 12)
            .padding(.top, 2)

            Divider().overlay(palette.line)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(palette.text)
                    .padding(12)
                    .textSelection(.enabled)
            }
        }
        .background(palette.background, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.line, lineWidth: 1)
        }
    }
}

private extension MarkdownBlock {
    var isCode: Bool {
        if case .code = kind { return true }
        return false
    }
}
