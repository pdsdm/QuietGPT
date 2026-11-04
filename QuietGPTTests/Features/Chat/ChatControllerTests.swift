import Foundation
import SwiftData
import Testing
@testable import QuietGPT

@MainActor
struct ChatControllerTests {
    private func makeController(reply: String = "one two three four five six seven eight") throws -> (ChatController, ModelContext) {
        let container = try ModelContainer(for: Conversation.self, Message.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let controller = ChatController()
        controller.attach(context)
        controller.simulateReplies(with: reply)
        return (controller, context)
    }

    private func waitUntilIdle(_ controller: ChatController) async {
        while controller.isResponding {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func savesTheReply() async throws {
        let (controller, _) = try makeController(reply: "hello there")

        controller.send("Hi")
        await waitUntilIdle(controller)

        let texts = controller.conversation?.orderedMessages.map(\.text)
        #expect(texts == ["Hi", "hello there"])
    }

    @Test func deletingTheChatDuringAReplyLeavesNothing() async throws {
        let (controller, context) = try makeController()

        controller.send("Hi")
        while controller.streamingText.isEmpty {
            try? await Task.sleep(for: .milliseconds(5))
        }
        let conversation = try #require(controller.conversation)
        controller.delete(conversation)

        #expect(!controller.isResponding)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(try context.fetch(FetchDescriptor<Conversation>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Message>()).isEmpty)
    }

    @Test func aDroppedReplyDoesNotEndTheNextOne() async throws {
        let (controller, _) = try makeController()

        controller.send("First")
        let first = try #require(controller.conversation)
        controller.delete(first)
        controller.send("Second")
        #expect(controller.isResponding)
        await waitUntilIdle(controller)

        let texts = controller.conversation?.orderedMessages.map(\.text)
        #expect(texts == ["Second", "one two three four five six seven eight"])
    }

    @Test func deleteAllDuringAReplyLeavesNothing() async throws {
        let (controller, context) = try makeController()

        controller.send("Hi")
        controller.deleteAll()
        try? await Task.sleep(for: .milliseconds(150))

        #expect(!controller.isResponding)
        #expect(controller.conversation == nil)
        #expect(try context.fetch(FetchDescriptor<Conversation>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Message>()).isEmpty)
    }

    @Test func tryAgainReplacesTheLastReply() async throws {
        let (controller, context) = try makeController(reply: "answer")

        controller.send("Question")
        await waitUntilIdle(controller)
        controller.regenerate()
        await waitUntilIdle(controller)

        let texts = controller.conversation?.orderedMessages.map(\.text)
        #expect(texts == ["Question", "answer"])
        #expect(try context.fetch(FetchDescriptor<Message>()).count == 2)
    }
}
