import Foundation
import FoundationModels

enum RewriteTone: String, CaseIterable, Identifiable {
    case kinder
    case shorter
    case longer
    case formal
    case english
    case spanish

    var id: Self { self }

    var title: String {
        switch self {
        case .kinder: "Kinder"
        case .shorter: "Shorter"
        case .longer: "Longer"
        case .formal: "Formal"
        case .english: "English"
        case .spanish: "Spanish"
        }
    }

    var request: String {
        switch self {
        case .kinder: "Make this message kinder and warmer. Keep the same meaning."
        case .shorter: "Make this message shorter. Keep the same meaning."
        case .longer: "Make this message a little longer and more complete. Keep the same meaning."
        case .formal: "Make this message polite and formal."
        case .english: "Translate this message into natural English."
        case .spanish: "Translate this message into natural Spanish."
        }
    }
}

struct Rewriter {
    private static let instructions = """
    You rewrite a short message that the user is about to send to another person. \
    Write as the user, in the first person. \
    Reply with the rewritten message only, with no quotes, notes or explanations. \
    Keep the language of the message unless you are asked to translate it.
    """

    private let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    var isAvailable: Bool {
        model.availability == .available
    }

    func prepare() {
        guard isAvailable else { return }
        LanguageModelSession(model: model, instructions: Self.instructions).prewarm()
    }

    func rewrite(_ text: String, tone: RewriteTone) -> AsyncThrowingStream<String, Error> {
        rewrite(text, request: tone.request)
    }

    func rewrite(_ text: String, request: String) -> AsyncThrowingStream<String, Error> {
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
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
            "Hush can't rewrite this one. Try another tone."
        case .unsupportedLanguageOrLocale:
            "Hush can't rewrite this language yet."
        default:
            "Hush can't rewrite right now. Check that Apple Intelligence is on in Settings."
        }
    }
}
