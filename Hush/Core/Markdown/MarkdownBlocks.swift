import Foundation

struct MarkdownBlock: Identifiable, Equatable {
    enum Kind: Equatable {
        case paragraph
        case heading
        case bullet
        case numbered(String)
        case code(language: String)
    }

    let id: Int
    let kind: Kind
    let text: String
    let start: Int
}

enum MarkdownBlocks {
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var paragraphStart = 0
        var code: [String]?
        var codeLanguage = ""
        var codeStart = 0
        var offset = 0

        func emit(_ kind: MarkdownBlock.Kind, _ text: String, at start: Int) {
            blocks.append(MarkdownBlock(id: blocks.count, kind: kind, text: text, start: start))
        }

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            emit(.paragraph, paragraph.joined(separator: "\n"), at: paragraphStart)
            paragraph.removeAll()
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
            } else if trimmed.hasPrefix("#") {
                flushParagraph()
                let text = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                emit(.heading, text, at: lineStart)
            } else if let item = bulletItem(trimmed) {
                flushParagraph()
                emit(.bullet, item, at: lineStart)
            } else if let (number, item) = numberedItem(trimmed) {
                flushParagraph()
                emit(.numbered(number), item, at: lineStart)
            } else {
                if paragraph.isEmpty { paragraphStart = lineStart }
                paragraph.append(line)
            }
        }

        if let lines = code {
            emit(.code(language: codeLanguage), lines.joined(separator: "\n"), at: codeStart)
        }
        flushParagraph()
        return blocks
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
