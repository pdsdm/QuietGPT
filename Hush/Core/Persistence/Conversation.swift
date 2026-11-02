import Foundation
import SwiftData

@Model
final class Conversation {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message] = []

    init(title: String, createdAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var orderedMessages: [Message] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }

    var preview: String {
        orderedMessages.last(where: { $0.role == .assistant })?.text
            ?? orderedMessages.last?.text
            ?? ""
    }
}
