import Foundation
import SwiftData

enum MessageRole: String, Codable {
    case user
    case assistant
}

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

@Model
final class Message {
    var id: UUID
    var roleValue: String
    var text: String
    var createdAt: Date
    var conversation: Conversation?

    init(role: MessageRole, text: String, createdAt: Date = .now) {
        self.id = UUID()
        self.roleValue = role.rawValue
        self.text = text
        self.createdAt = createdAt
    }

    var role: MessageRole {
        get { MessageRole(rawValue: roleValue) ?? .assistant }
        set { roleValue = newValue.rawValue }
    }
}
