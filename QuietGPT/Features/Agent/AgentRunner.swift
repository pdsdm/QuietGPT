import Foundation
import Observation

@MainActor
@Observable
final class AgentRunner {
    enum Phase: Equatable {
        case idle
        case working
        case approval(String)
        case handover(String)
        case finished(String)
        case stopped(String)
    }

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var detail: String
    }

    private static let maxSteps = 25
    private static let maxRepeats = 3
    private static let markDelay = Duration.milliseconds(700)

    private(set) var phase: Phase = .idle
    private(set) var log: [Entry] = []

    @ObservationIgnored let browser: AgentBrowser
    @ObservationIgnored private let engine: any AgentEngine
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var waiting: CheckedContinuation<Bool, Never>?

    init(engine: any AgentEngine = AppleAgentEngine()) {
        self.engine = engine
        browser = AgentBrowser()
    }

    var isActive: Bool {
        switch phase {
        case .working, .approval, .handover: true
        case .idle, .finished, .stopped: false
        }
    }

    var canThink: Bool {
        engine.isAvailable
    }

    func start(task: String, at url: URL) {
        begin(task: task) { self.browser.open(url) }
    }

    func start(task: String, html: String) {
        begin(task: task) { self.browser.open(html: html) }
    }

    func answer(_ allowed: Bool) {
        waiting?.resume(returning: allowed)
        waiting = nil
    }

    func stop() {
        job?.cancel()
        job = nil
        answer(false)
        if isActive {
            phase = .stopped(String(localized: "You stopped QuietGPT."))
        }
    }

    func reset() {
        stop()
        browser.close()
        log = []
        phase = .idle
    }

    private func begin(task: String, open: @escaping () -> Void) {
        stop()
        log = []
        phase = .working
        job = Task {
            do {
                open()
                try await self.run(task)
            } catch is CancellationError {
            } catch {
                self.phase = .stopped(ReplyEngine.message(for: error))
            }
        }
    }

    private func run(_ task: String) async throws {
        var done: [String] = []
        var last: AgentAction?
        var repeats = 0

        for _ in 0..<Self.maxSteps {
            try await browser.settle()
            let page = try await browser.snapshot()
            let decision = try await engine.next(task: task, page: page, done: done)
            try Task.checkCancellation()

            repeats = decision.action == last ? repeats + 1 : 1
            last = decision.action
            guard repeats < Self.maxRepeats else {
                phase = .stopped(String(localized: "QuietGPT repeated the same step and stopped."))
                return
            }

            let summary = AgentPrompt.summary(of: decision.action, on: page)

            switch decision.action {
            case .finish(let message):
                note(String(localized: "Done"), message.isEmpty ? decision.reason : message)
                phase = .finished(message.isEmpty ? decision.reason : message)
                return
            case .stop(let message):
                note(String(localized: "Stopped"), message.isEmpty ? decision.reason : message)
                phase = .stopped(message.isEmpty ? decision.reason : message)
                return
            case .scroll:
                note(String(localized: "Scroll down"), decision.reason)
                _ = await browser.perform(.scroll)
                done.append(summary)
            case .tap(let id), .type(let id, _), .select(let id, _):
                guard let element = page.element(id) else {
                    done.append("\(summary) (failed: no element with this number)")
                    continue
                }
                note(Self.title(for: decision.action, on: element), decision.reason)
                await browser.mark(id)
                try await Task.sleep(for: Self.markDelay)

                if element.secret {
                    _ = try await ask(.handover(element.name))
                    await browser.unmark(id)
                    done.append("the user filled [\(id)] \"\(element.name)\"")
                    continue
                }
                if case .tap = decision.action, element.needsApproval {
                    guard try await ask(.approval(element.name)) else {
                        await browser.unmark(id)
                        phase = .stopped(String(localized: "You did not allow this step."))
                        return
                    }
                }

                await browser.unmark(id)
                let result = await browser.perform(decision.action)
                done.append(result == "ok" ? summary : "\(summary) (failed: \(result))")
            }
        }
        phase = .stopped(String(localized: "QuietGPT used all its steps and stopped."))
    }

    private func ask(_ question: Phase) async throws -> Bool {
        phase = question
        let allowed = await withCheckedContinuation { waiting = $0 }
        try Task.checkCancellation()
        phase = .working
        return allowed
    }

    private func note(_ text: String, _ detail: String) {
        log.append(Entry(text: text, detail: detail))
    }

    private static func title(for action: AgentAction, on element: PageElement) -> String {
        switch action {
        case .type(_, let text):
            String(localized: "Type “\(text)” in “\(element.name)”")
        case .select(_, let option):
            String(localized: "Select “\(option)” in “\(element.name)”")
        default:
            String(localized: "Tap “\(element.name)”")
        }
    }
}
