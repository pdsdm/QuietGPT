import SwiftData
import SwiftUI

@main
struct HushApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Conversation.self, Message.self])
    }
}
