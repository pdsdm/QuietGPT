import Testing
@testable import QuietGPT

struct MarkdownBlocksTests {
    @Test func splitsParagraphsOnBlankLines() {
        let blocks = MarkdownBlocks.parse("First line\nsame paragraph\n\nSecond")
        #expect(blocks.map(\.kind) == [.paragraph, .paragraph])
        #expect(blocks.map(\.text) == ["First line\nsame paragraph", "Second"])
    }

    @Test func readsListsAndHeadings() {
        let blocks = MarkdownBlocks.parse("# Title\n- one\n* two\n3. three")
        #expect(blocks.map(\.kind) == [.heading(1), .bullet, .bullet, .numbered("3")])
        #expect(blocks.map(\.text) == ["Title", "one", "two", "three"])
    }

    @Test func readsFencedCode() {
        let blocks = MarkdownBlocks.parse("Look:\n```swift\nlet a = 1\nprint(a)\n```\nDone")
        #expect(blocks.map(\.kind) == [.paragraph, .code(language: "swift"), .paragraph])
        #expect(blocks[1].text == "let a = 1\nprint(a)")
    }

    @Test func keepsOpenCodeWhileStreaming() {
        let blocks = MarkdownBlocks.parse("```\nlet a")
        #expect(blocks.map(\.kind) == [.code(language: "")])
        #expect(blocks.first?.text == "let a")
    }

    @Test func tracksBlockStartOffsets() {
        let source = "Hello\n\n- item"
        let blocks = MarkdownBlocks.parse(source)
        #expect(blocks.map(\.start) == [0, 7])
        let item = source.index(source.startIndex, offsetBy: blocks[1].start)
        #expect(source[item...] == "- item")
    }

    @Test func readsHeadingLevelsRulesQuotesAndTables() {
        let blocks = MarkdownBlocks.parse("## Plan\n---\n> Note one\n> note two\n| A | B |\n|---|---|\n| 1 | 2 |\n#hashtag")
        #expect(blocks.map(\.kind) == [.heading(2), .rule, .quote, .table, .paragraph])
        #expect(blocks[2].text == "Note one\nnote two")
        #expect(MarkdownBlocks.cells("| 1 | 2 |") == ["1", "2"])
        #expect(MarkdownBlocks.isDivider("|---|:--:|"))
    }

    @Test func ignoresNumbersWithoutSpace() {
        let blocks = MarkdownBlocks.parse("3.14 is pi")
        #expect(blocks.map(\.kind) == [.paragraph])
    }
}
