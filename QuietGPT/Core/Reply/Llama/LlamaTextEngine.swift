import Foundation
import os
import UIKit

@MainActor
final class LlamaTextEngine: TextEngine {
    nonisolated private static let logger = Logger(subsystem: "QuietGPT", category: "llama")

    let store: WeightStore
    private var core: LlamaCore?
    private var running: OSAllocatedUnfairLock<Bool>?
    private var observers: [NSObjectProtocol] = []

    init(weights: Weights) {
        store = WeightStore(weights: weights)
        let center = NotificationCenter.default
        for name in [UIApplication.didReceiveMemoryWarningNotification, UIApplication.didEnterBackgroundNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    if notification.name == UIApplication.didEnterBackgroundNotification {
                        self?.release(because: "background", cancelling: true)
                    } else {
                        self?.release(because: "memory warning", cancelling: false)
                    }
                }
            })
        }
    }

    var isAvailable: Bool {
        store.state == .ready
    }

    var unavailableReply: String {
        switch store.state {
        case .downloading(let progress):
            "QuietGPT is still getting ready on this iPhone (\(Int(progress * 100)) %). Try again soon. Your chats stay on this device."
        case .verifying:
            "QuietGPT is almost ready on this iPhone. Try again in a moment. Your chats stay on this device."
        case .failed(let reason):
            "QuietGPT could not get ready on this iPhone (\(reason)). Your chats stay on this device."
        case .missing, .ready:
            "QuietGPT is getting ready on this iPhone. Try again soon. Your chats stay on this device."
        }
    }

    func prepare() {
        store.start()
    }

    func forget(_ conversationID: UUID) {
        guard let core else { return }
        core.queue.async { core.forget(conversationID) }
    }

    func forgetAll() {
        guard let core else { return }
        core.queue.async { core.forgetAll() }
    }

    func reply(to prompt: String, in conversationID: UUID, history: [ChatTurn], options: TextOptions) -> AsyncThrowingStream<String, Error> {
        let core = core ?? LlamaCore(path: store.fileURL.path)
        self.core = core
        let thinking = options.thinking
        let full = LFMPrompt.text(history: history, prompt: prompt, thinking: thinking)
        let next = LFMPrompt.next(prompt: prompt, thinking: thinking)
        let maxTokens = thinking ? LFMPrompt.thinkingTokens : LFMPrompt.replyTokens
        let turns = history.count
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        running = cancelled
        return AsyncThrowingStream { continuation in
            core.queue.async {
                do {
                    var raw = ""
                    var shown = ""
                    let metrics = try core.generate(
                        conversation: conversationID,
                        turns: turns,
                        full: full,
                        next: next,
                        maxTokens: maxTokens,
                        isCancelled: { cancelled.withLock { $0 } }
                    ) { text in
                        raw = text
                        let clean = LFMPrompt.clean(text, thinking: thinking, final: false)
                        if !clean.isEmpty, clean != shown {
                            shown = clean
                            continuation.yield(clean)
                        }
                    }
                    let final = LFMPrompt.clean(raw, thinking: thinking, final: true)
                    if final != shown {
                        continuation.yield(final)
                    }
                    Self.logger.notice("LFM3 metrics: \(metrics.summary, privacy: .public)")
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                cancelled.withLock { $0 = true }
            }
        }
    }

    #if DEBUG
    func complete(system: String, history: [ChatTurn], prompt: String) async throws -> (String, LlamaMetrics) {
        let core = core ?? LlamaCore(path: store.fileURL.path)
        self.core = core
        let full = LFMPrompt.text(system: system, history: history, prompt: prompt, thinking: false)
        let turns = history.count
        return try await withCheckedThrowingContinuation { continuation in
            core.queue.async {
                do {
                    var raw = ""
                    let metrics = try core.generate(conversation: UUID(), turns: turns, full: full, next: "", maxTokens: LFMPrompt.replyTokens, isCancelled: { false }) { raw = $0 }
                    continuation.resume(returning: (raw, metrics))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    #endif

    private func release(because reason: String, cancelling: Bool) {
        if cancelling {
            running?.withLock { $0 = true }
        }
        guard let core else { return }
        core.queue.async {
            core.unload()
            Self.logger.notice("LFM3 weights unloaded: \(reason, privacy: .public)")
        }
    }
}
