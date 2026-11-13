import Foundation
import FoundationModels

@MainActor
final class AppleTextEngine: TextEngine {
    private static let instructions = """
    You are QuietGPT, a private assistant that lives fully on the user's iPhone. \
    Nothing the user writes leaves the device. \
    Be warm and clear, like a knowledgeable friend. \
    When you explain or compare, say how it works step by step and what it means in practice for the user. \
    When you write something for the user, write the full text, ready to send. \
    Do not end with a question. Never invent a number, a date or a name. \
    Use Markdown lists or code blocks only when they help. \
    Never describe yourself as a model or an AI model. You are QuietGPT.
    """

    private static let recallTurns = 8
    private static let recallCharacters = 600

    private var sessions: [UUID: LanguageModelSession] = [:]

    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    var unavailableReply: String {
        switch SystemLanguageModel.default.availability {
        case .unavailable(.modelNotReady):
            String(localized: "Apple Intelligence is still getting ready on this iPhone. Try again soon. Your chats stay on this device.")
        case .unavailable(.deviceNotEligible):
            String(localized: "This iPhone does not support Apple Intelligence, so I can't answer here. Your chats stay on this device.")
        default:
            String(localized: "I can't think yet on this iPhone. QuietGPT needs Apple Intelligence. Turn it on in Settings, then Apple Intelligence & Siri. Your chats still stay on this device.")
        }
    }

    nonisolated static func translate(_ error: Error) -> Error {
        switch error as? LanguageModelSession.GenerationError {
        case .guardrailViolation, .refusal:
            TextEngineError.refused
        case .unsupportedLanguageOrLocale:
            TextEngineError.unsupportedLanguage
        case .rateLimited, .concurrentRequests:
            TextEngineError.busy
        case .exceededContextWindowSize:
            TextEngineError.tooLong
        case .assetsUnavailable:
            TextEngineError.notReady
        case .some:
            TextEngineError.failed
        case nil:
            error
        }
    }

    func prepare() {
        guard isAvailable else { return }
        LanguageModelSession(instructions: Self.instructions).prewarm()
    }

    func forget(_ conversationID: UUID) {
        sessions[conversationID] = nil
    }

    func forgetAll() {
        sessions.removeAll()
    }

    func reply(to prompt: String, in conversationID: UUID, history: [ChatTurn], options: TextOptions) -> AsyncThrowingStream<String, Error> {
        let session = session(for: conversationID, history: history)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await snapshot in session.streamResponse(to: prompt) {
                        try Task.checkCancellation()
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.translate(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func session(for conversationID: UUID, history: [ChatTurn]) -> LanguageModelSession {
        if let session = sessions[conversationID] {
            return session
        }
        let session = LanguageModelSession(instructions: Self.instructions(recalling: history))
        sessions[conversationID] = session
        return session
    }

    static func instructions(recalling history: [ChatTurn]) -> String {
        let recent = history.suffix(recallTurns)
        guard !recent.isEmpty else { return instructions }
        let recap = recent
            .map { "\($0.role == .user ? "User" : "QuietGPT"): \($0.text.prefix(recallCharacters))" }
            .joined(separator: "\n")
        return instructions + "\n\nThe conversation so far:\n" + recap
    }
}
