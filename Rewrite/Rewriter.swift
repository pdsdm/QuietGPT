import Foundation
import FoundationModels

struct Rewriter {
    private let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    var isAvailable: Bool {
        model.availability == .available
    }

    func prepare() {
        guard isAvailable else { return }
        session(usesRules: true).prewarm()
    }

    private func session(usesRules: Bool) -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: StyleStore.instructions(usesRules: usesRules))
    }

    func rewrite(_ text: String, style: RewriteStyle) -> AsyncThrowingStream<String, Error> {
        rewrite(text, request: style.prompt, usesRules: style.usesRules)
    }

    func rewrite(_ text: String, request: String, usesRules: Bool = true) -> AsyncThrowingStream<String, Error> {
        let session = session(usesRules: usesRules)
        let prompt = "\(request)\n\nMessage:\n\(text)"
        return AsyncThrowingStream { continuation in
            let meter = NetworkWatch.shared.startWriting()
            let task = Task {
                defer { NetworkWatch.shared.finishWriting(from: meter) }
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
            "QuietGPT can't rewrite this one. Try another style."
        case .unsupportedLanguageOrLocale:
            "QuietGPT can't rewrite this language yet."
        default:
            "QuietGPT can't rewrite right now. Check that Apple Intelligence is on in Settings."
        }
    }
}
