import Foundation

struct StylePack: Codable, Equatable {
    enum Failure: Error, Equatable {
        case tooLarge
        case unreadable
        case newerVersion
        case tooManyStyles
        case tooManyRules
        case textTooLong
        case empty
    }

    struct Merged: Equatable {
        var styles: [RewriteStyle]
        var rules: [String]
        var addedStyles: Int
        var addedRules: Int
        var skippedRules: Int
    }

    static let fileExtension = "quietgpt"
    static let currentVersion = 1
    static let maxBytes = 64 * 1024
    static let maxStyles = 30
    static let maxTitleLength = 40
    static let maxPromptLength = 500

    struct Item: Codable, Equatable, Identifiable {
        var id: String { "\(title)\n\(prompt)" }
        var title: String
        var prompt: String
        var usesRules: Bool
    }

    var version = StylePack.currentVersion
    var name: String
    var rules: [String]
    var styles: [Item]

    init(name: String, rules: [String], styles: [RewriteStyle]) {
        self.name = name
        self.rules = rules
        self.styles = styles.map { Item(title: $0.title, prompt: $0.prompt, usesRules: $0.usesRules) }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> StylePack {
        guard data.count <= maxBytes else { throw Failure.tooLarge }
        guard let pack = try? JSONDecoder().decode(StylePack.self, from: data) else { throw Failure.unreadable }
        guard pack.version <= currentVersion else { throw Failure.newerVersion }
        guard pack.styles.count <= maxStyles else { throw Failure.tooManyStyles }
        guard pack.rules.count <= StyleStore.maxRules else { throw Failure.tooManyRules }
        let shortRules = pack.rules.allSatisfy { $0.count <= StyleStore.maxRuleLength }
        let shortStyles = pack.styles.allSatisfy { $0.title.count <= maxTitleLength && $0.prompt.count <= maxPromptLength }
        guard shortRules, shortStyles, pack.name.count <= maxTitleLength else { throw Failure.textTooLong }
        let usable = pack.rules.contains { !$0.isBlank } || pack.styles.contains { !$0.title.isBlank && !$0.prompt.isBlank }
        guard usable else { throw Failure.empty }
        return pack
    }

    func merged(styles current: [RewriteStyle], rules currentRules: [String]) -> Merged {
        var result = Merged(styles: current, rules: currentRules, addedStyles: 0, addedRules: 0, skippedRules: 0)
        for item in styles where !item.title.isBlank && !item.prompt.isBlank {
            guard !result.styles.contains(where: { $0.title == item.title && $0.prompt == item.prompt }) else { continue }
            let fits = result.styles.count < Self.maxStyles
            result.styles.append(RewriteStyle(title: item.title, prompt: item.prompt, isOn: fits, usesRules: item.usesRules))
            result.addedStyles += 1
        }
        for rule in rules where !rule.isBlank {
            let clean = rule.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.rules.contains(clean) else { continue }
            guard result.rules.count < StyleStore.maxRules else {
                result.skippedRules += 1
                continue
            }
            result.rules.append(clean)
            result.addedRules += 1
        }
        return result
    }

    static func message(for error: Error) -> String {
        switch error as? Failure {
        case .tooLarge: "This file is too large to be a style pack."
        case .newerVersion: "This pack needs a newer version of QuietGPT."
        case .tooManyStyles, .tooManyRules, .textTooLong: "This pack is larger than QuietGPT allows."
        case .empty: "This pack has no styles or rules."
        default: "QuietGPT can't read this file."
        }
    }
}

private extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
