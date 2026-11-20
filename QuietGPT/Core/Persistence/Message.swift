import Foundation
import SwiftData

enum MessageRole: String, Codable {
    case user
    case assistant
}

@Model
final class Message {
    var id: UUID
    var roleValue: String
    var text: String
    var thought: String?
    var createdAt: Date
    var conversation: Conversation?

    init(role: MessageRole, text: String, thought: String? = nil, createdAt: Date = .now) {
        self.id = UUID()
        self.roleValue = role.rawValue
        self.text = text
        self.thought = thought
        self.createdAt = createdAt
    }

    var role: MessageRole {
        get { MessageRole(rawValue: roleValue) ?? .assistant }
        set { roleValue = newValue.rawValue }
    }
}
