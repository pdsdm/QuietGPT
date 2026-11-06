import SwiftData
import SwiftUI

@main
struct QuietGPTApp: App {
    private let store = ChatStore.open()

    init() {
        let group = StyleStore.group.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        try? StyleStore.excludeFromBackup(preferencesIn: group)
        StyleStore.savedLayout = StyleStore.options.layoutChoice
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
            switch store {
            case .saved(let container):
                RootView(chatsAreTemporary: false)
                    .modelContainer(container)
            case .temporary(let container):
                RootView(chatsAreTemporary: true)
                    .modelContainer(container)
            case .failed:
                StoreFailureScreen()
            }
        }
    }
}
