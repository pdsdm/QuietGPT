import Foundation
import Testing
@testable import QuietGPT

private let bookingPage = """
<html><head><title>Casa Test</title></head><body>
<h1>Book a table</h1>
<a href="#menu">Menu</a>
<form onsubmit="event.preventDefault(); document.getElementById('result').innerText = 'Booked for ' + document.getElementById('name').value + ', ' + document.getElementById('people').value + ' people';">
<label for="name">Your name</label><input id="name" type="text">
<label for="people">People</label>
<select id="people"><option value="1">1 person</option><option value="2">2 people</option><option value="3">3 people</option></select>
<input id="secret" type="password" aria-label="Password">
<input type="hidden" name="token" value="x">
<button type="submit">Reserve</button>
</form>
<h2 id="result"></h2>
</body></html>
"""

private let slowLoad = Duration.seconds(120)

private final class ScriptedEngine: AgentEngine, @unchecked Sendable {
    private var steps: [(PageSnapshot) -> AgentAction]
    private(set) var prompts: [[String]] = []

    init(_ steps: [(PageSnapshot) -> AgentAction]) {
        self.steps = steps
    }

    var isAvailable: Bool { true }

    func next(task: String, page: PageSnapshot, done: [String]) async throws -> AgentDecision {
        prompts.append(done)
        let step = steps.isEmpty ? { _ in AgentAction.stop("no more steps") } : steps.removeFirst()
        return AgentDecision(action: step(page), reason: "test")
    }
}

private func id(_ label: String, in page: PageSnapshot) -> Int {
    page.elements.first { $0.label == label }?.id ?? -1
}

@MainActor
struct AgentTests {
    private func loaded() async throws -> AgentBrowser {
        let browser = AgentBrowser(loadTimeout: slowLoad)
        browser.open(html: bookingPage)
        try await browser.settle()
        return browser
    }

    private func wait(for runner: AgentRunner, until done: (AgentRunner.Phase) -> Bool) async {
        for _ in 0..<3600 where !done(runner.phase) {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func result(on runner: AgentRunner) async throws -> String? {
        try await runner.browser.webView.evaluateJavaScript("document.getElementById('result').innerText") as? String
    }

    @Test func snapshotListsWhatTheUserCanUse() async throws {
        let page = try await loaded().snapshot()

        #expect(page.title == "Casa Test")
        #expect(page.text.contains("Book a table"))
        #expect(page.elements.map(\.label) == ["Your name", "People", "Password", "Reserve", "Menu"])
        #expect(page.elements.map(\.kind) == ["field", "list", "field", "button", "link"])
        #expect(page.elements[1].options == ["1 person", "2 people", "3 people"])
        #expect(page.elements[1].value == "1 person")
        #expect(page.elements[2].secret)
        #expect(page.elements.map(\.id) == [1, 2, 3, 4, 5])
    }

    @Test func actionsChangeThePage() async throws {
        let browser = try await loaded()
        let page = try await browser.snapshot()

        #expect(await browser.perform(.type(id("Your name", in: page), "Ana \"O'Neil\"")) == "ok")
        #expect(await browser.perform(.select(id("People", in: page), "2 people")) == "ok")
        #expect(await browser.perform(.select(id("People", in: page), "9 people")) == "no such option")
        #expect(await browser.perform(.type(id("Reserve", in: page), "x")) == "not a field")
        #expect(await browser.perform(.tap(99)) == "missing")
        #expect(await browser.perform(.tap(id("Reserve", in: page))) == "ok")

        let after = try await browser.snapshot()
        #expect(after.text.contains("Booked for Ana \"O'Neil\", 2 people"))
        #expect(after.elements.first { $0.label == "Your name" }?.value == "Ana \"O'Neil\"")
    }

    @Test func runnerAsksBeforeTheFinalTap() async throws {
        let engine = ScriptedEngine([
            { .type(id("Your name", in: $0), "Ana") },
            { .select(id("People", in: $0), "3 people") },
            { .tap(id("Reserve", in: $0)) },
            { .finish($0.text) }
        ])
        let runner = AgentRunner(engine: engine, loadTimeout: slowLoad)
        runner.start(task: "Book for 3, name Ana", html: bookingPage)

        await wait(for: runner) { $0 != .working }
        #expect(runner.phase == .approval("Reserve"))
        #expect(try await result(on: runner) == "")

        runner.answer(true)
        await wait(for: runner) { !runner.isActive && $0 != .working }

        guard case .finished(let message) = runner.phase else {
            Issue.record("phase is \(runner.phase)")
            return
        }
        #expect(message.contains("Booked for Ana, 3 people"))
        #expect(runner.log.count == 4)
        #expect(engine.prompts.last?.count == 3)
    }

    @Test func runnerStopsWhenTheUserSaysNo() async throws {
        let engine = ScriptedEngine([{ .tap(id("Reserve", in: $0)) }])
        let runner = AgentRunner(engine: engine, loadTimeout: slowLoad)
        runner.start(task: "Book", html: bookingPage)

        await wait(for: runner) { $0 != .working }
        runner.answer(false)
        await wait(for: runner) { _ in !runner.isActive }

        guard case .stopped = runner.phase else {
            Issue.record("phase is \(runner.phase)")
            return
        }
        #expect(try await result(on: runner) == "")
    }

    @Test func runnerNeverTypesASecret() async throws {
        let engine = ScriptedEngine([
            { .type(id("Password", in: $0), "hunter2") },
            { _ in .stop("end") }
        ])
        let runner = AgentRunner(engine: engine, loadTimeout: slowLoad)
        runner.start(task: "Log in", html: bookingPage)

        await wait(for: runner) { $0 != .working }
        #expect(runner.phase == .handover("Password"))
        runner.answer(true)
        await wait(for: runner) { _ in !runner.isActive }

        let value = try await runner.browser.webView.evaluateJavaScript("document.getElementById('secret').value") as? String
        #expect(value == "")
    }

    @Test func runnerStopsARepeatedStep() async throws {
        let engine = ScriptedEngine(Array(repeating: { _ in AgentAction.scroll }, count: 5))
        let runner = AgentRunner(engine: engine, loadTimeout: slowLoad)
        runner.start(task: "Loop", html: bookingPage)

        await wait(for: runner) { !runner.isActive && $0 != .working }
        guard case .stopped = runner.phase else {
            Issue.record("phase is \(runner.phase)")
            return
        }
        #expect(engine.prompts.count == 3)
    }

    @Test func approvalWords() {
        func element(_ label: String, kind: String = "button") -> PageElement {
            PageElement(id: 1, kind: kind, type: "", label: label, value: "", options: [], secret: false)
        }
        #expect(element("Reserve").needsApproval)
        #expect(element("Confirmar reserva").needsApproval)
        #expect(element("Pay now").needsApproval)
        #expect(!element("Find a table").needsApproval)
        #expect(!element("Facebook").needsApproval)
        #expect(!element("Reserve", kind: "field").needsApproval)
    }

    @Test func promptShowsTheTaskTheStepsAndTheElements() {
        let page = PageSnapshot(title: "Casa Test", url: "https://casa.example/book", text: "Book a table", elements: [
            PageElement(id: 1, kind: "field", type: "date", label: "Day", value: "2026-11-13", options: [], secret: false),
            PageElement(id: 2, kind: "list", type: "", label: "People", value: "1 person", options: ["1 person", "2 people"], secret: false)
        ])
        let text = AgentPrompt.text(task: "Book for 2", page: page, done: ["tap [3] \"Open\""], today: Date(timeIntervalSince1970: 1_794_500_000))

        #expect(text.contains("Task: Book for 2"))
        #expect(text.contains("Page: Casa Test (casa.example)"))
        #expect(text.contains("1. tap [3] \"Open\""))
        #expect(text.contains("[1] field(date) \"Day\" = \"2026-11-13\""))
        #expect(text.contains("[2] list \"People\" = \"1 person\" options: 1 person | 2 people"))
    }

    @Test func addressesAlwaysUseHTTPS() {
        #expect(AgentBrowser.address(from: " example.com/book ")?.absoluteString == "https://example.com/book")
        #expect(AgentBrowser.address(from: "http://example.com")?.absoluteString == "https://example.com")
        #expect(AgentBrowser.address(from: "https://example.com")?.absoluteString == "https://example.com")
        #expect(AgentBrowser.address(from: "file:///etc/passwd") == nil)
        #expect(AgentBrowser.address(from: "javascript://x.y") == nil)
        #expect(AgentBrowser.address(from: "two words") == nil)
        #expect(AgentBrowser.address(from: "localhost") == nil)
    }
}
