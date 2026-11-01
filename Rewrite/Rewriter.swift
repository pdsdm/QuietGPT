import Foundation
import FoundationModels

struct Rewriter {
    private let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    var isAvailable: Bool {
        model.availability == .available
    }

    func prepare() {
        guard isAvailable else { return }
        LanguageModelSession(model: model, instructions: StyleStore.instructions).prewarm()
    }

    func rewrite(_ text: String, style: RewriteStyle) -> AsyncThrowingStream<String, Error> {
        rewrite(text, request: style.prompt)
    }

    func rewrite(_ text: String, request: String) -> AsyncThrowingStream<String, Error> {
        let session = LanguageModelSession(model: model, instructions: StyleStore.instructions)
        let prompt = "\(request)\n\nMessage:\n\(text)"
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await snapshot in session.streamResponse(to: prompt) {
                        try Task.checkCancellation()
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func message(for error: Error) -> String {
        switch error as? LanguageModelSession.GenerationError {
        case .guardrailViolation, .refusal:
            "Hush can't rewrite this one. Try another style."
        case .unsupportedLanguageOrLocale:
            "Hush can't rewrite this language yet."
        default:
            "Hush can't rewrite right now. Check that Apple Intelligence is on in Settings."
        }
    }
}
