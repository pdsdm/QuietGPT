import Foundation

enum TextEngineError: Error, Equatable {
    case notReady
    case refused
    case unsupportedLanguage
    case busy
    case tooLong
    case failed
}

struct TextOptions: Equatable {
    var thinking = false
}

@MainActor
protocol TextEngine: AnyObject {
    var isAvailable: Bool { get }
    var unavailableReply: String { get }
    func prepare()
    func reply(to prompt: String, in conversationID: UUID, history: [ChatTurn], options: TextOptions) -> AsyncThrowingStream<String, Error>
    func forget(_ conversationID: UUID)
    func forgetAll()
}

enum TextEngineKind: String, CaseIterable {
    case apple

    static var selected: TextEngineKind {
        #if DEBUG
        if let kind = DebugLaunch.engine {
            return kind
        }
        if let name = UserDefaults.standard.string(forKey: SettingsKey.textEngine), let kind = TextEngineKind(rawValue: name) {
            return kind
        }
        #endif
        return .apple
    }

    @MainActor
    func make() -> any TextEngine {
        switch self {
        case .apple:
            AppleTextEngine()
        }
    }
}
