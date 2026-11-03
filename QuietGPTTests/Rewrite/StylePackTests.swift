import Foundation
import Testing
@testable import QuietGPT

struct StylePackTests {
    private let sample = RewriteStyle(title: "Clear", prompt: "Make this clear.", usesRules: false)

    private func json(rules: [String] = ["No emoji"], styles: String = "[]", name: String = "Pack", version: Int = 1) -> Data {
        let list = try! String(decoding: JSONEncoder().encode(rules), as: UTF8.self)
        return Data(#"{"version":\#(version),"name":"\#(name)","rules":\#(list),"styles":\#(styles)}"#.utf8)
    }

    @Test func roundTrip() throws {
        let pack = StylePack(name: "Team", rules: ["No emoji"], styles: [sample])
        let decoded = try StylePack.decode(pack.encoded())

        #expect(decoded == pack)
        #expect(decoded.styles.first?.usesRules == false)
    }

    @Test func rejectsLargeFile() {
        let data = Data(count: StylePack.maxBytes + 1)

        #expect(throws: StylePack.Failure.tooLarge) { try StylePack.decode(data) }
    }

    @Test func rejectsBadJSON() {
        #expect(throws: StylePack.Failure.unreadable) { try StylePack.decode(Data("not a pack".utf8)) }
    }

    @Test func rejectsNewerVersion() {
        #expect(throws: StylePack.Failure.newerVersion) { try StylePack.decode(json(version: StylePack.currentVersion + 1)) }
    }

    @Test func rejectsTooManyStyles() throws {
        let item = #"{"title":"A","prompt":"B","usesRules":true}"#
        let styles = "[" + Array(repeating: item, count: StylePack.maxStyles + 1).joined(separator: ",") + "]"

        #expect(throws: StylePack.Failure.tooManyStyles) { try StylePack.decode(json(styles: styles)) }
    }

    @Test func rejectsTooManyRules() {
        let rules = (0...StyleStore.maxRules).map { "Rule \($0)" }

        #expect(throws: StylePack.Failure.tooManyRules) { try StylePack.decode(json(rules: rules)) }
    }

    @Test func rejectsLongText() {
        let rule = String(repeating: "a", count: StyleStore.maxRuleLength + 1)

        #expect(throws: StylePack.Failure.textTooLong) { try StylePack.decode(json(rules: [rule])) }
    }

    @Test func rejectsEmptyPack() {
        #expect(throws: StylePack.Failure.empty) { try StylePack.decode(json(rules: ["  "])) }
    }

    @Test func mergeGivesNewIDsAndKeepsCurrentItems() {
        let current = RewriteStyle(title: "Mine", prompt: "My prompt.")
        let pack = StylePack(name: "Team", rules: ["No emoji"], styles: [sample])
        let merged = pack.merged(styles: [current], rules: ["Short"])

        #expect(merged.styles.count == 2)
        #expect(merged.styles[0] == current)
        #expect(merged.styles[1].id != sample.id)
        #expect(merged.styles[1].usesRules == false)
        #expect(merged.rules == ["Short", "No emoji"])
        #expect(merged.addedStyles == 1)
        #expect(merged.addedRules == 1)
    }

    @Test func mergeSkipsDuplicates() {
        let pack = StylePack(name: "Team", rules: ["No emoji"], styles: [sample])
        let merged = pack.merged(styles: [sample], rules: ["No emoji"])

        #expect(merged.styles == [sample])
        #expect(merged.rules == ["No emoji"])
        #expect(merged.addedStyles == 0)
        #expect(merged.addedRules == 0)
    }

    @Test func mergeTurnsOffStylesAboveTheLimit() {
        let current = (0..<StylePack.maxStyles).map { RewriteStyle(title: "S\($0)", prompt: "P\($0)") }
        let merged = StylePack(name: "Team", rules: [], styles: [sample]).merged(styles: current, rules: [])

        #expect(merged.styles.last?.title == "Clear")
        #expect(merged.styles.last?.isOn == false)
    }

    @Test func mergeCountsRulesAboveTheLimit() {
        let current = (0..<StyleStore.maxRules).map { "Rule \($0)" }
        let merged = StylePack(name: "Team", rules: ["New rule"], styles: []).merged(styles: [], rules: current)

        #expect(merged.rules == current)
        #expect(merged.skippedRules == 1)
    }

    @Test func initialsUseTwoWords() {
        #expect(RewriteStyle(title: "Mum", prompt: "").initials == "M")
        #expect(RewriteStyle(title: "my boss anna", prompt: "").initials == "MB")
    }
}
