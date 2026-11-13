import Foundation
import Testing
@testable import QuietGPT

@MainActor
final class FakeTextEngine: TextEngine {
    var replies: [Result<String, TextEngineError>]
    var prompts: [String] = []
    var histories: [[ChatTurn]] = []
    var forgotten: [UUID] = []
    var isAvailable = true
    var unavailableReply = "Not ready."

    init(_ replies: [Result<String, TextEngineError>]) {
        self.replies = replies
    }

    func prepare() {}

    func reply(to prompt: String, in conversationID: UUID, history: [ChatTurn], options: TextOptions) -> AsyncThrowingStream<String, Error> {
        prompts.append(prompt)
        histories.append(history)
        let next = replies.removeFirst()
        return AsyncThrowingStream { continuation in
            switch next {
            case .success(let text):
                continuation.yield(text)
                continuation.finish()
            case .failure(let error):
                continuation.finish(throwing: error)
            }
        }
    }

    func forget(_ conversationID: UUID) {
        forgotten.append(conversationID)
    }

    func forgetAll() {}
}

@MainActor
struct ReplyEngineTests {
    private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var last = ""
        for try await text in stream {
            last = text
        }
        return last
    }

    private func history(_ count: Int) -> [ChatTurn] {
        (1...count).map { ChatTurn(role: $0.isMultiple(of: 2) ? .assistant : .user, text: "Turn number \($0) about the weather") }
    }

    @Test func retriesWithShorterHistoryWhenTheChatIsTooLong() async throws {
        let engine = FakeTextEngine([.failure(.tooLong), .success("It will be sunny all week, with a light wind in the afternoon.")])
        let reply = ReplyEngine(engine: engine)
        let chat = UUID()

        let text = try await collect(reply.reply(to: "And tomorrow?", in: chat, history: history(10)))

        #expect(text == "It will be sunny all week, with a light wind in the afternoon.")
        #expect(engine.forgotten == [chat])
        #expect(engine.histories.map(\.count) == [10, 4])
        #expect(engine.histories[1].last?.text == "Turn number 10 about the weather")
    }

    @Test func appleEngineRecallsTheLastEightTurns() {
        let instructions = AppleTextEngine.instructions(recalling: history(10))

        #expect(!instructions.contains("Turn number 2 "))
        #expect(instructions.contains("User: Turn number 3 "))
        #expect(instructions.contains("QuietGPT: Turn number 10 "))
    }

    @Test func asksAgainInTheLanguageOfThePrompt() async throws {
        let prompt = "dame una receta de tortilla para cuatro personas"
        let spanish = "Pela las patatas, córtalas finas y fríelas despacio con la cebolla."
        let engine = FakeTextEngine([.success("Here is a simple recipe for a potato omelette for four people."), .success(spanish)])
        let reply = ReplyEngine(engine: engine)
        let chat = UUID()

        let text = try await collect(reply.reply(to: prompt, in: chat, history: []))

        #expect(text == spanish)
        #expect(engine.forgotten == [chat])
        #expect(engine.prompts == [prompt, ReplyEngine.firm(prompt, in: "es")])
    }

    @Test func passesOtherErrorsThrough() async {
        let engine = FakeTextEngine([.failure(.refused)])
        let reply = ReplyEngine(engine: engine)

        await #expect(throws: TextEngineError.refused) {
            try await collect(reply.reply(to: "Hello there", in: UUID(), history: []))
        }
    }

    @Test func answersWithTheEngineTextWhenItIsNotAvailable() async throws {
        let engine = FakeTextEngine([])
        engine.isAvailable = false
        let reply = ReplyEngine(engine: engine)

        let text = try await collect(reply.reply(to: "Hello there", in: UUID(), history: []))

        #expect(text == "Not ready.")
        #expect(engine.prompts.isEmpty)
    }

    @Test func showsOneMessageForEachEngineError() {
        let errors: [TextEngineError] = [.notReady, .refused, .unsupportedLanguage, .busy, .tooLong, .failed]
        let messages = Set(errors.map { ReplyEngine.message(for: $0) })

        #expect(messages.count == errors.count)
        #expect(ReplyEngine.message(for: CancellationError()) == ReplyEngine.message(for: TextEngineError.failed))
    }

    @Test func keepsErrorsThatAreNotFromTheAppleEngine() {
        #expect(AppleTextEngine.translate(CancellationError()) is CancellationError)
    }
}

struct TextEngineKindTests {
    @Test func usesTheAppleEngineByDefault() {
        #expect(TextEngineKind.selected == .apple)
        #expect(TextEngineKind.allCases == [.apple, .lfm3])
    }
}
