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
        #expect(blocks.map(\.kind) == [.heading, .bullet, .bullet, .numbered("3")])
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

    @Test func ignoresNumbersWithoutSpace() {
        let blocks = MarkdownBlocks.parse("3.14 is pi")
        #expect(blocks.map(\.kind) == [.paragraph])
    }
}
