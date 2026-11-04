import Foundation
import Observation
import OSLog
import SwiftData

@MainActor
@Observable
final class ChatController {
    enum Phase: Equatable {
        case idle
        case thinking
        case streaming
    }

    private(set) var conversation: Conversation?
    private(set) var phase: Phase = .idle
    private(set) var streamingText = ""
    private(set) var completedReplies = 0
    private(set) var liveMetrics: ReplyMetrics?
    private(set) var lastMetrics: ReplyMetrics?
    var draft = ""

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "quietgpt", category: "chat")

    private let engine: ReplyEngine
    private var context: ModelContext?
    private var task: Task<Void, Never>?
    private var reply: (token: UUID, conversationID: UUID)?
    private var meter: [String: UInt32]?

    init(engine: ReplyEngine? = nil) {
        self.engine = engine ?? ReplyEngine()
    }

    var isResponding: Bool { phase != .idle }

    var hasConversation: Bool {
        guard let conversation else { return false }
        return !conversation.messages.isEmpty
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding
    }

    func attach(_ context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        engine.prepare()
    }

    func open(_ conversation: Conversation) {
        stop()
        self.conversation = conversation
    }

    func startNew() {
        stop()
        conversation = nil
        draft = ""
    }

    func send(_ suggestion: String? = nil) {
        let prompt = (suggestion ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isResponding, let context else { return }

        let conversation = self.conversation ?? makeConversation(titled: prompt, in: context)
        let history = conversation.orderedMessages.map { ChatTurn(role: $0.role, text: $0.text) }
        append(Message(role: .user, text: prompt), to: conversation)
        draft = ""
        streamingText = ""
        phase = .thinking
        liveMetrics = ReplyMetrics()

        let token = UUID()
        reply = (token, conversation.id)
        meter = NetworkWatch.shared.startWriting()
        let stream = engine.reply(to: prompt, in: conversation.id, history: history)
        task = Task { [weak self] in
            do {
                for try await text in stream {
                    guard let self, self.reply?.token == token else { return }
                    self.liveMetrics?.received(text)
                    if self.phase == .thinking { self.phase = .streaming }
                    self.streamingText = text
                }
                self?.finishReply(token, in: conversation)
            } catch is CancellationError {
                self?.finishReply(token, in: conversation)
            } catch {
                Self.logger.error("Reply failed: \(String(describing: error), privacy: .public)")
                self?.finishReply(token, in: conversation, fallback: ReplyEngine.message(for: error))
            }
        }
    }

    #if DEBUG
    func simulateReplies(with text: String) {
        engine.simulatedReply = text
    }
    #endif

    func stop() {
        task?.cancel()
        task = nil
    }

    func regenerate() {
        guard !isResponding, let conversation, let context else { return }
        let ordered = conversation.orderedMessages
        guard let lastUser = ordered.last(where: { $0.role == .user }) else { return }
        let prompt = lastUser.text
        let start = lastUser.createdAt
        let removed = ordered.filter { $0.createdAt >= start }
        conversation.messages.removeAll { message in removed.contains { $0.id == message.id } }
        for message in removed {
            context.delete(message)
        }
        try? context.save()
        engine.forget(conversation.id)
        send(prompt)
    }

    func delete(_ conversation: Conversation) {
        guard let context else { return }
        if conversation.id == reply?.conversationID {
            dropReply()
        }
        if conversation.id == self.conversation?.id {
            startNew()
        }
        engine.forget(conversation.id)
        context.delete(conversation)
        try? context.save()
    }

    func deleteAll() {
        guard let context else { return }
        dropReply()
        startNew()
        engine.forgetAll()
        for conversation in (try? context.fetch(FetchDescriptor<Conversation>())) ?? [] {
            context.delete(conversation)
        }
        try? context.save()
    }

    private func dropReply() {
        task?.cancel()
        task = nil
        reply = nil
        liveMetrics = nil
        streamingText = ""
        phase = .idle
    }

    private func makeConversation(titled prompt: String, in context: ModelContext) -> Conversation {
        let title = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
        let conversation = Conversation(title: String(title.prefix(Conversation.titleLength)))
        context.insert(conversation)
        self.conversation = conversation
        return conversation
    }

    private func append(_ message: Message, to conversation: Conversation) {
        message.conversation = conversation
        conversation.messages.append(message)
        conversation.updatedAt = message.createdAt
        try? context?.save()
    }

    private func finishReply(_ token: UUID, in conversation: Conversation, fallback: String? = nil) {
        guard reply?.token == token else { return }
        reply = nil
        NetworkWatch.shared.finishWriting(from: meter)
        let text = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = text.isEmpty ? (fallback ?? "") : text
        if !final.isEmpty {
            append(Message(role: .assistant, text: final), to: conversation)
        }
        if var metrics = liveMetrics {
            metrics.finish()
            Self.logger.notice("Reply metrics: \(metrics.summary, privacy: .public)")
            lastMetrics = metrics
        }
        liveMetrics = nil
        streamingText = ""
        phase = .idle
        task = nil
        completedReplies += 1
    }
}
