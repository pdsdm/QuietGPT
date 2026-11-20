import Foundation

struct MarkdownBlock: Identifiable, Equatable {
    enum Kind: Equatable {
        case paragraph
        case heading(Int)
        case bullet
        case quote
        case table
        case rule
        case numbered(String)
        case code(language: String)
    }

    let id: Int
    let kind: Kind
    let text: String
    let start: Int

    var streamsAsText: Bool {
        switch kind {
        case .table, .rule: false
        default: true
        }
    }
}

enum MarkdownBlocks {
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var paragraphStart = 0
        var paragraphKind = MarkdownBlock.Kind.paragraph
        var code: [String]?
        var codeLanguage = ""
        var codeStart = 0
        var offset = 0

        func emit(_ kind: MarkdownBlock.Kind, _ text: String, at start: Int) {
            blocks.append(MarkdownBlock(id: blocks.count, kind: kind, text: text, start: start))
        }

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            emit(paragraphKind, paragraph.joined(separator: "\n"), at: paragraphStart)
            paragraph.removeAll()
            paragraphKind = .paragraph
        }

        func collect(_ kind: MarkdownBlock.Kind, _ text: String, at start: Int) {
            if paragraphKind != kind { flushParagraph() }
            if paragraph.isEmpty { paragraphStart = start }
            paragraphKind = kind
            paragraph.append(text)
        }

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let lineStart = offset
            offset += line.count + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if let lines = code {
                    emit(.code(language: codeLanguage), lines.joined(separator: "\n"), at: codeStart)
                    code = nil
                } else {
                    flushParagraph()
                    code = []
                    codeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeStart = offset
                }
                continue
            }

            if code != nil {
                code?.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
            } else if isRule(trimmed) {
                flushParagraph()
                emit(.rule, "", at: lineStart)
            } else if let (level, text) = heading(trimmed) {
                flushParagraph()
                emit(.heading(level), text, at: lineStart)
            } else if trimmed.hasPrefix(">") {
                collect(.quote, trimmed.dropFirst().trimmingCharacters(in: .whitespaces), at: lineStart)
            } else if trimmed.hasPrefix("|") {
                collect(.table, trimmed, at: lineStart)
            } else if let item = bulletItem(trimmed) {
                flushParagraph()
                emit(.bullet, item, at: lineStart)
            } else if let (number, item) = numberedItem(trimmed) {
                flushParagraph()
                emit(.numbered(number), item, at: lineStart)
            } else {
                collect(.paragraph, line, at: lineStart)
            }
        }

        if let lines = code {
            emit(.code(language: codeLanguage), lines.joined(separator: "\n"), at: codeStart)
        }
        flushParagraph()
        return blocks
    }

    static func cells(_ row: String) -> [String] {
        var line = row.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("|") { line.removeFirst() }
        if line.hasSuffix("|") { line.removeLast() }
        return line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func isDivider(_ row: String) -> Bool {
        let cells = cells(row)
        return !cells.isEmpty && cells.allSatisfy { cell in !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" } }
    }

    private static func isRule(_ line: String) -> Bool {
        guard line.count >= 3, let first = line.first, "-*_".contains(first) else { return false }
        return line.allSatisfy { $0 == first || $0 == " " }
    }

    private static func heading(_ line: String) -> (Int, String)? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.isEmpty || rest.hasPrefix(" ") else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func bulletItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func numberedItem(_ line: String) -> (String, String)? {
        guard let dot = line.firstIndex(of: "."), dot != line.startIndex else { return nil }
        let number = line[..<dot]
        guard number.count <= 3, number.allSatisfy(\.isNumber) else { return nil }
        let rest = line[line.index(after: dot)...]
        guard rest.hasPrefix(" ") else { return nil }
        return (String(number), String(rest.dropFirst()))
    }
}

extension AttributedString {
    static func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
