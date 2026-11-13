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
    case lfm3

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

    static var weights: Weights {
        #if DEBUG
        if DebugLaunch.weights == "q4" {
            return .q4
        }
        #endif
        return .q8
    }

    @MainActor
    func make() -> any TextEngine {
        switch self {
        case .apple:
            AppleTextEngine()
        case .lfm3:
            LlamaTextEngine(weights: Self.weights)
        }
    }
}
