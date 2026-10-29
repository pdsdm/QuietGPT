import Foundation
import FoundationModels

struct ChatTurn {
    let role: MessageRole
    let text: String
}

@MainActor
final class ReplyEngine {
    private static let instructions = """
    You are Hush, a private assistant that lives fully on the user's iPhone. \
    Nothing the user writes leaves the device. \
    Be calm, warm and clear. Prefer short paragraphs. \
    Use Markdown lists or code blocks only when they help. \
    Never describe yourself as a model or an AI model. You are Hush.
    """

    private static let unavailableReply = """
    I can't think yet on this iPhone. Hush needs Apple Intelligence. \
    Turn it on in Settings, then Apple Intelligence & Siri. \
    Your chats still stay on this device.
    """

    private var sessions: [UUID: LanguageModelSession] = [:]

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

    func reply(to prompt: String, in conversationID: UUID, history: [ChatTurn]) -> AsyncThrowingStream<String, Error> {
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
                        try await self.stream(prompt, conversationID: conversationID, history: Array(history.suffix(4)), into: continuation)
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
        let recent = history.suffix(8)
        guard !recent.isEmpty else { return instructions }
        let recap = recent
            .map { "\($0.role == .user ? "User" : "Hush"): \($0.text.prefix(600))" }
            .joined(separator: "\n")
        return instructions + "\n\nThe conversation so far:\n" + recap
    }

    private static func simulatedStream(_ text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var output = ""
                for word in text.split(separator: " ", omittingEmptySubsequences: false) {
                    try? await Task.sleep(for: .milliseconds(45))
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
