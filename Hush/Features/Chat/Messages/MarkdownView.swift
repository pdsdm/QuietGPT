import SwiftUI

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
            styled(block.text)
                .font(HushFont.title)
                .foregroundStyle(palette.text)
        case .bullet, .numbered, .paragraph:
            styled(block.text)
                .font(HushFont.body)
                .foregroundStyle(palette.text)
                .modifier(BlockChrome(kind: block.kind))
        }
    }

    private func styled(_ text: String) -> Text {
        let string = AttributedString.inlineMarkdown(text)
        return string.runs.reduce(Text("")) { partial, run in
            let intent = run.inlinePresentationIntent ?? []
            var piece = Text(AttributedString(string[run.range].characters))
            if intent.contains(.code) {
                piece = piece.font(.system(.callout, design: .monospaced)).foregroundStyle(palette.accentText)
            } else {
                if intent.contains(.stronglyEmphasized) {
                    piece = piece.fontWeight(.medium)
                }
                if intent.contains(.emphasized) {
                    piece = piece.italic()
                }
            }
            return Text("\(partial)\(piece)")
        }
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
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .numbered(let number):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(number)
                    .font(HushFont.mono)
                    .foregroundStyle(palette.text3)
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
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

private extension MarkdownBlock {
    var isCode: Bool {
        if case .code = kind { return true }
        return false
    }
}
