import Foundation
import FoundationModels

protocol AgentEngine: Sendable {
    var isAvailable: Bool { get }
    func next(task: String, page: PageSnapshot, done: [String]) async throws -> AgentDecision
}

@Generable
enum AgentVerb {
    case tap
    case type
    case select
    case scroll
    case finish
    case stop
}

@Generable
struct AgentStep {
    @Guide(description: "One short sentence that says why this is the next step")
    var reason: String
    @Guide(description: "The next step")
    var action: AgentVerb
    @Guide(description: "The number of the element from the list. 0 for scroll, finish and stop")
    var element: Int
    @Guide(description: "The text to type, the option to select, or a short message for the user. Empty for tap and scroll")
    var text: String

    var decision: AgentDecision {
        let action: AgentAction = switch action {
        case .tap: .tap(element)
        case .type: .type(element, text)
        case .select: .select(element, text)
        case .scroll: .scroll
        case .finish: .finish(text)
        case .stop: .stop(text)
        }
        return AgentDecision(action: action, reason: reason)
    }
}

struct AppleAgentEngine: AgentEngine {
    private static let shortElementLimit = 25

    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    func next(task: String, page: PageSnapshot, done: [String]) async throws -> AgentDecision {
        do {
            return try await ask(AgentPrompt.text(task: task, page: page, done: done))
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            return try await ask(AgentPrompt.text(task: task, page: page, done: Array(done.suffix(6)), elementLimit: Self.shortElementLimit, includesText: false))
        }
    }

    private func ask(_ prompt: String) async throws -> AgentDecision {
        let session = LanguageModelSession(instructions: AgentPrompt.instructions)
        let response = try await session.respond(to: prompt, generating: AgentStep.self, options: GenerationOptions(sampling: .greedy))
        return response.content.decision
    }
}
