import Foundation

@MainActor
final class FallbackTextEngine: TextEngine {
    private let main: any TextEngine
    private let fallback: any TextEngine

    init(main: any TextEngine, fallback: any TextEngine) {
        self.main = main
        self.fallback = fallback
    }

    private var current: any TextEngine {
        guard main.isAvailable else { return fallback }
        if main.readiness == .setup, fallback.isAvailable { return fallback }
        return main
    }

    var isAvailable: Bool {
        main.isAvailable || fallback.isAvailable
    }

    var unavailableReply: String {
        main.isAvailable ? main.unavailableReply : fallback.unavailableReply
    }

    var supportsThinking: Bool {
        current.supportsThinking
    }

    var readiness: TextReadiness {
        current === main ? main.readiness : .ready
    }

    func prepare() {
        main.prepare()
        if current !== main {
            fallback.prepare()
        }
    }

    func reply(to prompt: String, in conversationID: UUID, history: [ChatTurn], options: TextOptions) -> AsyncThrowingStream<String, Error> {
        current.reply(to: prompt, in: conversationID, history: history, options: options)
    }

    func forget(_ conversationID: UUID) {
        main.forget(conversationID)
        fallback.forget(conversationID)
    }

    func forgetAll() {
        main.forgetAll()
        fallback.forgetAll()
    }
}
