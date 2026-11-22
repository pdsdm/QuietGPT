import Foundation

enum TextEngineError: Error, Equatable {
    case notReady
    case refused
    case unsupportedLanguage
    case busy
    case tooLong
    case failed
}

struct TextOptions {
    var thinking = false
    var onThought: (@Sendable (String) -> Void)?
}

@MainActor
protocol TextEngine: AnyObject {
    var isAvailable: Bool { get }
    var unavailableReply: String { get }
    var supportsThinking: Bool { get }
    func prepare()
    func reply(to prompt: String, in conversationID: UUID, history: [ChatTurn], options: TextOptions) -> AsyncThrowingStream<String, Error>
    func forget(_ conversationID: UUID)
    func forgetAll()
}

extension TextEngine {
    var supportsThinking: Bool { false }
}

enum TextEngineKind: String, CaseIterable {
    case apple
    #if DEBUG
    case lfm3
    #endif
    case lfm3ane = "lfm3-ane"

    static var selected: TextEngineKind {
        #if DEBUG
        if let kind = DebugLaunch.engine {
            return kind
        }
        if let name = UserDefaults.standard.string(forKey: SettingsKey.textEngine), let kind = TextEngineKind(rawValue: name) {
            return kind
        }
        #endif
        return CoreMLTextEngine.isInstalled ? .lfm3ane : .apple
    }

    #if DEBUG
    static var weights: Weights {
        DebugLaunch.weights == "q4" ? .q4 : .q8
    }
    #endif

    @MainActor
    func make() -> any TextEngine {
        switch self {
        case .apple:
            AppleTextEngine()
        #if DEBUG
        case .lfm3:
            LlamaTextEngine(weights: Self.weights)
        #endif
        case .lfm3ane:
            CoreMLTextEngine()
        }
    }
}
