import SwiftUI

struct StreamingMessage: View {
    let text: String
    var thought = ""
    let isThinking: Bool

    @Environment(\.palette) private var palette
    @State private var arrivals: [StreamArrival] = []
    @State private var seen = 0

    var body: some View {
        AssistantBox {
            VStack(alignment: .leading, spacing: 10) {
                if !thought.isEmpty {
                    ThoughtBox(text: thought, isLive: text.isEmpty)
                }
                if isThinking && text.isEmpty {
                    if thought.isEmpty {
                        ThinkingGlyphs()
                            .transition(.blurReplace)
                    }
                } else {
                    content
                        .transition(.blurReplace)
                }
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

    private static func font(for block: MarkdownBlock) -> Font {
        if block.isCode { return QuietGPTFont.mono }
        if case .heading(let level) = block.kind { return MarkdownBlockView.headingFont(level) }
        return QuietGPTFont.body
    }

    @ViewBuilder
    private var content: some View {
        let blocks = MarkdownBlocks.parse(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                if block.id == blocks.last?.id, block.streamsAsText {
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        StreamingText(
                            text: block.text,
                            arrivals: arrivals,
                            offset: block.start,
                            font: Self.font(for: block),
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
        case .heading(let level):
            styled(block.text)
                .font(Self.headingFont(level))
                .foregroundStyle(palette.text)
                .padding(.top, level <= 2 ? 4 : 0)
        case .rule:
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
                .padding(.vertical, 4)
        case .table:
            MarkdownTable(text: block.text, cell: styled)
        case .bullet, .numbered, .paragraph, .quote:
            styled(block.text)
                .font(QuietGPTFont.body)
                .foregroundStyle(palette.text)
                .modifier(BlockChrome(kind: block.kind))
        }
    }

    static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: QuietGPTFont.title
        case 2: QuietGPTFont.lead
        default: QuietGPTFont.headline
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
                    piece = piece.fontWeight(.semibold)
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
                    .font(QuietGPTFont.mono)
                    .foregroundStyle(palette.text3)
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .code:
            content
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.background, in: .rect(cornerRadius: Radius.medium, style: .continuous))
        case .quote:
            HStack(spacing: 10) {
                Capsule()
                    .fill(palette.accent.opacity(0.6))
                    .frame(width: 3)
                content
                    .foregroundStyle(palette.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .paragraph, .heading, .table, .rule:
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

private struct MarkdownTable: View {
    let text: String
    let cell: (String) -> Text

    @Environment(\.palette) private var palette

    var body: some View {
        let rows = text.split(separator: "\n").map(String.init).filter { !MarkdownBlocks.isDivider($0) }.map(MarkdownBlocks.cells)
        let width = rows.map(\.count).max() ?? 0
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(0..<width, id: \.self) { column in
                            cell(column < row.count ? row[column] : "")
                                .font(QuietGPTFont.callout)
                                .fontWeight(index == 0 ? .semibold : .regular)
                                .foregroundStyle(index == 0 ? palette.text : palette.text2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 220, alignment: .leading)
                        }
                    }
                    if index == 0 {
                        Rectangle()
                            .fill(palette.line)
                            .frame(height: 1)
                            .gridCellUnsizedAxes(.horizontal)
                    }
                }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
        .background(palette.background, in: .rect(cornerRadius: Radius.medium, style: .continuous))
    }
}
