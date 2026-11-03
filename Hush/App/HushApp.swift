import SwiftData
import SwiftUI

@main
struct HushApp: App {
    init() {
        let bar = UINavigationBar.appearance()
        if let title = BrandFont.uiFont(size: 17, weight: .medium) {
            bar.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: title)]
        }
        if let large = BrandFont.uiFont(size: 34) {
            bar.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)]
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Conversation.self, Message.self])
    }
}
