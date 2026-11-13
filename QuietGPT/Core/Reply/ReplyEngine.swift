import Foundation

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

    private static let recallTurns = 8
    private static let retryTurns = 4
    private static let languageTurns = 3
    private static let recallCharacters = 600
    private static let simulatedWordDelay = Duration.milliseconds(45)

    private let engine: any TextEngine

    #if DEBUG
    var simulatedReply: String?
    #endif

    init(engine: (any TextEngine)? = nil) {
        self.engine = engine ?? TextEngineKind.selected.make()
    }

    static func message(for error: Error) -> String {
        switch error as? TextEngineError {
        case .refused:
            String(localized: "I would rather not answer that one. Try asking in another way.")
        case .unsupportedLanguage:
            String(localized: "I can't answer in this language yet.")
        case .busy:
            String(localized: "I need a moment. Please try again.")
        case .tooLong:
            String(localized: "This chat is too long for me now. Please start a new chat.")
        case .notReady:
            String(localized: "Apple Intelligence is still getting ready on this iPhone. Try again soon. Your chats stay on this device.")
        default:
            String(localized: "I can't think on this iPhone right now. Check that Apple Intelligence is on and ready in Settings, then try again.")
        }
    }

    var isAvailable: Bool {
        engine.isAvailable
    }

    func prepare() {
        engine.prepare(instructions: Self.instructions)
    }

    func forget(_ conversationID: UUID) {
        engine.forget(conversationID)
    }

    func forgetAll() {
        engine.forgetAll()
    }

    func reply(to prompt: String, in conversationID: UUID, history: [ChatTurn]) -> AsyncThrowingStream<String, Error> {
        #if DEBUG
        if let simulatedReply {
            return Self.simulatedStream(simulatedReply)
        }
        #endif
        guard isAvailable else {
            return Self.simulatedStream(engine.unavailableReply)
        }

        let expected = Self.language(of: prompt, after: history)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.answer(prompt, expected: expected, conversationID: conversationID, history: history, into: continuation)
                    continuation.finish()
                } catch TextEngineError.tooLong {
                    self.engine.forget(conversationID)
                    do {
                        try await self.answer(prompt, expected: expected, conversationID: conversationID, history: Array(history.suffix(Self.retryTurns)), into: continuation)
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

    static func language(of prompt: String, after history: [ChatTurn], likely: [String] = TextLanguage.likely) -> String? {
        let earlier = history.filter { $0.role == .user }.suffix(languageTurns).map(\.text)
        guard !(earlier + [prompt]).contains(where: { TextLanguage.namesLanguage($0, likely: likely) }) else { return nil }
        if TextLanguage.code(of: prompt, likely: likely) != nil {
            return TextLanguage.single(of: prompt, likely: likely)
        }
        return earlier.reversed().lazy.compactMap { TextLanguage.single(of: $0, likely: likely) }.first
    }

    static func firm(_ prompt: String, in language: String) -> String {
        guard let name = TextLanguage.name(of: language) else { return prompt }
        return "\(prompt)\n\nReply in \(name)."
    }

    private func answer(
        _ prompt: String,
        expected: String?,
        conversationID: UUID,
        history: [ChatTurn],
        into continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        guard let expected else {
            _ = try await stream(prompt, expected: nil, conversationID: conversationID, history: history, into: continuation)
            return
        }
        if try await stream(prompt, expected: expected, conversationID: conversationID, history: history, into: continuation) {
            return
        }
        engine.forget(conversationID)
        _ = try await stream(Self.firm(prompt, in: expected), expected: nil, conversationID: conversationID, history: history, into: continuation)
    }

    private func stream(
        _ prompt: String,
        expected: String?,
        conversationID: UUID,
        history: [ChatTurn],
        into continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws -> Bool {
        let replies = engine.reply(to: prompt, in: conversationID, instructions: Self.instructions(recalling: history), options: TextOptions())
        var output = ""
        var isSettled = expected == nil
        for try await snapshot in replies {
            try Task.checkCancellation()
            output = snapshot
            if !isSettled, let expected {
                guard TextLanguage.letters(in: output) >= TextLanguage.settledLetters else { continue }
                guard !TextLanguage.differs(output, from: expected) else { return false }
                isSettled = true
            }
            continuation.yield(output)
        }
        if !isSettled {
            if let expected, TextLanguage.differs(output, from: expected) {
                return false
            }
            continuation.yield(output)
        }
        return true
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
