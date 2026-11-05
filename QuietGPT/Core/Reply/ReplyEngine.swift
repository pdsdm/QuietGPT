import Foundation
import FoundationModels

struct ChatTurn {
    let role: MessageRole
    let text: String
}

@MainActor
final class ReplyEngine {
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

    private static var unavailableReply: String {
        switch SystemLanguageModel.default.availability {
        case .unavailable(.modelNotReady):
            String(localized: "Apple Intelligence is still getting ready on this iPhone. Try again soon. Your chats stay on this device.")
        case .unavailable(.deviceNotEligible):
            String(localized: "This iPhone does not support Apple Intelligence, so I can't answer here. Your chats stay on this device.")
        default:
            String(localized: "I can't think yet on this iPhone. QuietGPT needs Apple Intelligence. Turn it on in Settings, then Apple Intelligence & Siri. Your chats still stay on this device.")
        }
    }

    private static let recallTurns = 8
    private static let retryTurns = 4
    private static let recallCharacters = 600
    private static let simulatedWordDelay = Duration.milliseconds(45)

    private var sessions: [UUID: LanguageModelSession] = [:]

    #if DEBUG
    var simulatedReply: String?
    #endif

    static func message(for error: Error) -> String {
        switch error as? LanguageModelSession.GenerationError {
        case .guardrailViolation, .refusal:
            String(localized: "I would rather not answer that one. Try asking in another way.")
        case .unsupportedLanguageOrLocale:
            String(localized: "I can't answer in this language yet.")
        case .rateLimited, .concurrentRequests:
            String(localized: "I need a moment. Please try again.")
        case .exceededContextWindowSize:
            String(localized: "This chat is too long for me now. Please start a new chat.")
        case .assetsUnavailable:
            String(localized: "Apple Intelligence is still getting ready on this iPhone. Try again soon. Your chats stay on this device.")
        default:
            String(localized: "I can't think on this iPhone right now. Check that Apple Intelligence is on and ready in Settings, then try again.")
        }
    }

    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
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

    func reply(to prompt: String, in conversationID: UUID, history: [ChatTurn]) -> AsyncThrowingStream<String, Error> {
        #if DEBUG
        if let simulatedReply {
            return Self.simulatedStream(simulatedReply)
        }
        #endif
        guard isAvailable else {
            return Self.simulatedStream(Self.unavailableReply)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.stream(prompt, conversationID: conversationID, history: history, into: continuation)
                    continuation.finish()
                } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                    self.sessions[conversationID] = nil
                    do {
                        try await self.stream(prompt, conversationID: conversationID, history: Array(history.suffix(Self.retryTurns)), into: continuation)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func stream(
        _ prompt: String,
        conversationID: UUID,
        history: [ChatTurn],
        into continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let session = session(for: conversationID, history: history)
        for try await snapshot in session.streamResponse(to: prompt) {
            try Task.checkCancellation()
            continuation.yield(snapshot.content)
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

    private static func instructions(recalling history: [ChatTurn]) -> String {
        let recent = history.suffix(recallTurns)
        guard !recent.isEmpty else { return instructions }
        let recap = recent
            .map { "\($0.role == .user ? "User" : "QuietGPT"): \($0.text.prefix(recallCharacters))" }
            .joined(separator: "\n")
        return instructions + "\n\nThe conversation so far:\n" + recap
    }

    private static func simulatedStream(_ text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var output = ""
                for word in text.split(separator: " ", omittingEmptySubsequences: false) {
                    try? await Task.sleep(for: simulatedWordDelay)
                    if Task.isCancelled { break }
                    output += output.isEmpty ? String(word) : " " + word
                    continuation.yield(output)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
