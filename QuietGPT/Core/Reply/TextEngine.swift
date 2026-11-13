import Foundation

enum TextEngineError: Error, Equatable {
    case notReady
    case refused
    case unsupportedLanguage
    case busy
    case tooLong
    case failed
}

struct TextOptions: Equatable {
    var thinking = false
}

@MainActor
protocol TextEngine: AnyObject {
    var isAvailable: Bool { get }
    var unavailableReply: String { get }
    func prepare(instructions: String)
    func reply(to prompt: String, in conversationID: UUID, instructions: String, options: TextOptions) -> AsyncThrowingStream<String, Error>
    func forget(_ conversationID: UUID)
    func forgetAll()
}
