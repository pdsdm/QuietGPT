import Foundation
import FoundationModels

@MainActor
final class AppleTextEngine: TextEngine {
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

    func prepare(instructions: String) {
        guard isAvailable else { return }
        LanguageModelSession(instructions: instructions).prewarm()
    }

    func forget(_ conversationID: UUID) {
        sessions[conversationID] = nil
    }

    func forgetAll() {
        sessions.removeAll()
    }

    func reply(to prompt: String, in conversationID: UUID, instructions: String, options: TextOptions) -> AsyncThrowingStream<String, Error> {
        let session = session(for: conversationID, instructions: instructions)
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

    private func session(for conversationID: UUID, instructions: String) -> LanguageModelSession {
        if let session = sessions[conversationID] {
            return session
        }
        let session = LanguageModelSession(instructions: instructions)
        sessions[conversationID] = session
        return session
    }
}
