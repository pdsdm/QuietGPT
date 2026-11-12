import Foundation
import WebKit

@MainActor
final class AgentBrowser: NSObject, WKNavigationDelegate {
    enum Failure: Error {
        case unreadablePage
    }

    private static let settleDelay = Duration.milliseconds(600)
    private static let pollDelay = Duration.milliseconds(100)

    let webView: WKWebView
    private let loadTimeout: Duration
    private var isNavigating = false

    init(loadTimeout: Duration = .seconds(15)) {
        self.loadTimeout = loadTimeout
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init()
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
    }

    static func address(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let lowered = trimmed.lowercased()
        let full: String
        if lowered.hasPrefix("https://") {
            full = trimmed
        } else if lowered.hasPrefix("http://") {
            full = "https://" + trimmed.dropFirst("http://".count)
        } else if trimmed.contains("://") {
            return nil
        } else {
            full = "https://" + trimmed
        }
        guard let url = URL(string: full), let host = url.host(), host.contains(".") else { return nil }
        return url
    }

    static func clearData() async {
        let store = WKWebsiteDataStore.default()
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    func open(_ url: URL) {
        isNavigating = true
        webView.load(URLRequest(url: url))
    }

    func open(html: String) {
        isNavigating = true
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isNavigating = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isNavigating = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isNavigating = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isNavigating = false
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isNavigating = false
    }

    func close() {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    func settle() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + loadTimeout
        try await Task.sleep(for: Self.pollDelay)
        while isNavigating || webView.isLoading, clock.now < deadline {
            try await Task.sleep(for: Self.pollDelay)
        }
        try await Task.sleep(for: Self.settleDelay)
    }

    func snapshot(limit: Int = 60, textLimit: Int = 500) async throws -> PageSnapshot {
        let result = try await webView.callAsyncJavaScript(
            PageScript.snapshot,
            arguments: ["limit": limit, "textLimit": textLimit],
            contentWorld: .defaultClient
        )
        guard let json = result as? String, let data = json.data(using: .utf8) else { throw Failure.unreadablePage }
        return try JSONDecoder().decode(PageSnapshot.self, from: data)
    }

    func mark(_ id: Int) async {
        _ = await run("mark", on: id)
    }

    func unmark(_ id: Int) async {
        _ = await run("unmark", on: id)
    }

    func perform(_ action: AgentAction) async -> String {
        switch action {
        case .tap(let id):
            return await run("tap", on: id)
        case .type(let id, let text):
            return await run("type", on: id, text: text)
        case .select(let id, let option):
            return await run("select", on: id, text: option)
        case .scroll:
            let result = try? await webView.callAsyncJavaScript(PageScript.scroll, contentWorld: .defaultClient)
            return result as? String ?? "failed"
        case .finish, .stop:
            return "ok"
        }
    }

    private func run(_ verb: String, on id: Int, text: String = "") async -> String {
        let result = try? await webView.callAsyncJavaScript(
            PageScript.act,
            arguments: ["id": String(id), "verb": verb, "text": text],
            contentWorld: .defaultClient
        )
        return result as? String ?? "failed"
    }
}
