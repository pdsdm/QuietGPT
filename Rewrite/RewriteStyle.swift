import Foundation

struct RewriteStyle: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var prompt: String
    var isOn: Bool

    init(id: UUID = UUID(), title: String, prompt: String, isOn: Bool = true) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.isOn = isOn
    }

    static let builtIn: [RewriteStyle] = [
        RewriteStyle(id: UUID(uuidString: "6B0F7C1E-0001-4000-8000-000000000001")!, title: "Kinder", prompt: "Make this message kinder and warmer. Keep the same meaning."),
        RewriteStyle(id: UUID(uuidString: "6B0F7C1E-0001-4000-8000-000000000002")!, title: "Shorter", prompt: "Make this message shorter. Keep the same meaning."),
        RewriteStyle(id: UUID(uuidString: "6B0F7C1E-0001-4000-8000-000000000003")!, title: "Longer", prompt: "Make this message a little longer and more complete. Keep the same meaning."),
        RewriteStyle(id: UUID(uuidString: "6B0F7C1E-0001-4000-8000-000000000004")!, title: "Formal", prompt: "Make this message polite and formal."),
        RewriteStyle(id: UUID(uuidString: "6B0F7C1E-0001-4000-8000-000000000005")!, title: "Fix", prompt: "Fix the spelling, grammar and punctuation. Change nothing else."),
        RewriteStyle(id: UUID(uuidString: "6B0F7C1E-0001-4000-8000-000000000006")!, title: "English", prompt: "Translate this message into natural English."),
        RewriteStyle(id: UUID(uuidString: "6B0F7C1E-0001-4000-8000-000000000007")!, title: "Spanish", prompt: "Translate this message into natural Spanish.")
    ]
}

enum KeyboardLanguage: String, Codable, CaseIterable, Identifiable {
    case automatic
    case english
    case spanish

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .english: "English (US)"
        case .spanish: "Spanish"
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
    var language = KeyboardLanguage.automatic

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoCapitalize = try container.decodeIfPresent(Bool.self, forKey: .autoCapitalize) ?? autoCapitalize
        periodShortcut = try container.decodeIfPresent(Bool.self, forKey: .periodShortcut) ?? periodShortcut
        showsAsk = try container.decodeIfPresent(Bool.self, forKey: .showsAsk) ?? showsAsk
        language = (try? container.decodeIfPresent(KeyboardLanguage.self, forKey: .language)) ?? language
    }
}

enum StyleStore {
    static let group = Bundle.main.object(forInfoDictionaryKey: "HushAppGroup") as? String

    static let defaultInstructions = """
    You rewrite a short message that the user is about to send to another person. \
    Write as the user, in the first person. \
    Reply with the rewritten message only, with no quotes, notes or explanations. \
    Keep the language of the message unless you are asked to translate it.
    """

    private static let stylesKey = "styles"
    private static let instructionsKey = "instructions"
    private static let optionsKey = "keyboardOptions"

    static var shared: UserDefaults {
        group.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    static var styles: [RewriteStyle] {
        get { decode([RewriteStyle].self, stylesKey) ?? RewriteStyle.builtIn }
        set { encode(newValue, stylesKey) }
    }

    static var enabledStyles: [RewriteStyle] {
        styles.filter { $0.isOn && !$0.title.isEmpty && !$0.prompt.isEmpty }
    }

    static var instructions: String {
        get {
            let value = shared.string(forKey: instructionsKey) ?? ""
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultInstructions : value
        }
        set { shared.set(newValue, forKey: instructionsKey) }
    }

    static var options: KeyboardOptions {
        get { decode(KeyboardOptions.self, optionsKey) ?? KeyboardOptions() }
        set { encode(newValue, optionsKey) }
    }

    static func reset() {
        shared.removeObject(forKey: stylesKey)
        shared.removeObject(forKey: instructionsKey)
        shared.removeObject(forKey: optionsKey)
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
