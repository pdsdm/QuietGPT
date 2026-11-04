import Foundation

struct RewriteStyle: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var prompt: String
    var isOn: Bool
    var usesRules: Bool

    init(id: UUID = UUID(), title: String, prompt: String, isOn: Bool = true, usesRules: Bool? = nil) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.isOn = isOn
        self.usesRules = usesRules ?? !Self.withoutRules.contains(id)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        prompt = try container.decode(String.self, forKey: .prompt)
        isOn = try container.decode(Bool.self, forKey: .isOn)
        usesRules = try container.decodeIfPresent(Bool.self, forKey: .usesRules) ?? !Self.withoutRules.contains(id)
    }

    var initials: String {
        title.split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap(\.first)
            .map { String($0).uppercased() }
            .joined()
    }

    private static let withoutRules: Set<UUID> = [
        UUID(uuidString: "6B0F7C1E-0001-4000-8000-000000000005")!,
        UUID(uuidString: "6B0F7C1E-0001-4000-8000-000000000006")!,
        UUID(uuidString: "6B0F7C1E-0001-4000-8000-000000000007")!
    ]

    static var builtIn: [RewriteStyle] { [
        RewriteStyle(id: UUID(uuidString: "6B0F7C1E-0001-4000-8000-000000000001")!, title: String(localized: "Kinder", bundle: Rewriter.bundle), prompt: "Make this message kinder and warmer. Keep the same meaning."),
        RewriteStyle(id: UUID(uuidString: "6B0F7C1E-0001-4000-8000-000000000002")!, title: String(localized: "Shorter", bundle: Rewriter.bundle), prompt: "Make this message shorter. Keep the same meaning."),
        RewriteStyle(id: UUID(uuidString: "6B0F7C1E-0001-4000-8000-000000000003")!, title: String(localized: "Longer", bundle: Rewriter.bundle), prompt: "Make this message a little longer and more complete. Keep the same meaning."),
        RewriteStyle(id: UUID(uuidString: "6B0F7C1E-0001-4000-8000-000000000004")!, title: String(localized: "Formal", bundle: Rewriter.bundle), prompt: "Make this message polite and formal."),
        RewriteStyle(id: UUID(uuidString: "6B0F7C1E-0001-4000-8000-000000000005")!, title: String(localized: "Fix", bundle: Rewriter.bundle), prompt: "Fix the spelling, grammar and punctuation. Change nothing else."),
        RewriteStyle(id: UUID(uuidString: "6B0F7C1E-0001-4000-8000-000000000006")!, title: String(localized: "English", bundle: Rewriter.bundle), prompt: "Translate this message into natural English."),
        RewriteStyle(id: UUID(uuidString: "6B0F7C1E-0001-4000-8000-000000000007")!, title: String(localized: "Spanish", bundle: Rewriter.bundle), prompt: "Translate this message into natural Spanish.")
    ] }
}

enum KeyboardLanguage: String, Codable, CaseIterable, Identifiable {
    case automatic
    case english
    case spanish

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: String(localized: "Automatic", bundle: Rewriter.bundle)
        case .english: String(localized: "English (US)", bundle: Rewriter.bundle)
        case .spanish: String(localized: "Spanish", bundle: Rewriter.bundle)
        }
    }

    var isSpanish: Bool {
        switch self {
        case .automatic:
            let language = Locale.preferredLanguages.first ?? "en"
            return language.hasPrefix("es") || language.hasPrefix("ca")
        case .english:
            return false
        case .spanish:
            return true
        }
    }
}

struct KeyboardOptions: Codable, Equatable {
    var autoCapitalize = true
    var periodShortcut = true
    var showsAsk = true
    var language = KeyboardLanguage.automatic {
        didSet { languageDate = .now }
    }
    var languageDate: Date?

    init() {}

    mutating func adopt(_ local: LanguageChoice?) {
        guard let local, let date = local.date, date > languageDate ?? .distantPast else { return }
        language = local.language
        languageDate = date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoCapitalize = try container.decodeIfPresent(Bool.self, forKey: .autoCapitalize) ?? autoCapitalize
        periodShortcut = try container.decodeIfPresent(Bool.self, forKey: .periodShortcut) ?? periodShortcut
        showsAsk = try container.decodeIfPresent(Bool.self, forKey: .showsAsk) ?? showsAsk
        language = (try? container.decodeIfPresent(KeyboardLanguage.self, forKey: .language)) ?? language
        languageDate = try container.decodeIfPresent(Date.self, forKey: .languageDate)
    }
}

struct LanguageChoice: Codable, Equatable {
    var language: KeyboardLanguage
    var date: Date?
}

enum RewriteUndo {
    static func cursorFollows(_ written: String, before: String) -> Bool {
        !before.isEmpty && (before.hasSuffix(written) || written.hasSuffix(before))
    }
}

enum StyleStore {
    static let group = Bundle.main.object(forInfoDictionaryKey: "QuietGPTAppGroup") as? String

    static let defaultInstructions = """
    You rewrite a short message that the user is about to send to another person. \
    Write as the user, in the first person. \
    Reply with the rewritten message only, with no quotes, notes or explanations. \
    Keep the language of the message unless you are asked to translate it.
    """

    static let maxRules = 10
    static let maxRuleLength = 120

    private static let stylesKey = "styles"
    private static let instructionsKey = "instructions"
    private static let optionsKey = "keyboardOptions"
    private static let rulesKey = "rules"
    private static let peopleKey = "people"
    private static let localLanguageKey = "localLanguage"

    static var shared: UserDefaults {
        group.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    static var styles: [RewriteStyle] {
        get { decode([RewriteStyle].self, stylesKey) ?? RewriteStyle.builtIn }
        set { encode(newValue, stylesKey) }
    }

    static var enabledStyles: [RewriteStyle] {
        enabled(styles)
    }

    static var people: [RewriteStyle] {
        get { decode([RewriteStyle].self, peopleKey) ?? [] }
        set { encode(newValue, peopleKey) }
    }

    static var enabledPeople: [RewriteStyle] {
        enabled(people)
    }

    static var allEnabled: [RewriteStyle] {
        enabledPeople + enabledStyles
    }

    private static func enabled(_ values: [RewriteStyle]) -> [RewriteStyle] {
        values.filter { $0.isOn && !$0.title.isEmpty && !$0.prompt.isEmpty }
    }

    static var instructions: String {
        get {
            let value = shared.string(forKey: instructionsKey) ?? ""
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultInstructions : value
        }
        set { shared.set(newValue, forKey: instructionsKey) }
    }

    static var rules: [String] {
        get { decode([String].self, rulesKey) ?? [] }
        set { encode(newValue, rulesKey) }
    }

    static func instructions(usesRules: Bool) -> String {
        compose(base: instructions, rules: usesRules ? rules : [])
    }

    static func compose(base: String, rules: [String]) -> String {
        let clean = rules
            .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxRuleLength)) }
            .filter { !$0.isEmpty }
            .prefix(maxRules)
        guard !clean.isEmpty else { return base }
        let lines = clean.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return "\(base)\n\nAlways follow these rules from the user:\n\(lines)"
    }

    static var options: KeyboardOptions {
        get { decode(KeyboardOptions.self, optionsKey) ?? KeyboardOptions() }
        set { encode(newValue, optionsKey) }
    }

    static var localLanguage: LanguageChoice? {
        get {
            UserDefaults.standard.data(forKey: localLanguageKey).flatMap { try? JSONDecoder().decode(LanguageChoice.self, from: $0) }
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: localLanguageKey)
        }
    }

    static func excludeFromBackup(preferencesIn container: URL?) throws {
        guard var folder = container?.appending(path: "Library/Preferences", directoryHint: .isDirectory) else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }

    static func reset() {
        shared.removeObject(forKey: stylesKey)
        shared.removeObject(forKey: instructionsKey)
        shared.removeObject(forKey: optionsKey)
        shared.removeObject(forKey: rulesKey)
        shared.removeObject(forKey: peopleKey)
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, _ key: String) -> Value? {
        guard let data = shared.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<Value: Encodable>(_ value: Value, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        shared.set(data, forKey: key)
    }
}
