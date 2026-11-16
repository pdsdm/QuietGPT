import Foundation
import os
import UIKit

@MainActor
final class CoreMLTextEngine: TextEngine {
    nonisolated private static let logger = Logger(subsystem: "QuietGPT", category: "coreml")
    nonisolated static let bundleName = "lfm3-lut8-2048-app"

    nonisolated static var folder: URL {
        WeightStore.folder.appending(path: bundleName, directoryHint: .isDirectory)
    }

    nonisolated static var compiledFolder: URL {
        WeightStore.folder.appending(path: bundleName + "-compiled", directoryHint: .isDirectory)
    }

    nonisolated private static let shared = CoreMLCore(folder: folder, compiledFolder: compiledFolder)

    private let core = CoreMLTextEngine.shared
    private var running: OSAllocatedUnfairLock<Bool>?
    private var observers: [NSObjectProtocol] = []

    init() {
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
        FileManager.default.fileExists(atPath: Self.folder.appending(path: "manifest.json").path)
    }

    var unavailableReply: String {
        "QuietGPT is getting ready on this iPhone. Try again soon. Your chats stay on this device."
    }

    func prepare() {
        guard isAvailable else { return }
        let core = core
        core.queue.async {
            guard !core.isLoaded else { return }
            let started = Date()
            do {
                try core.warm(prefix: LFMPrompt.prefix())
                let seconds = Date().timeIntervalSince(started)
                Self.logger.notice("Core ML parts loaded in \(seconds, format: .fixed(precision: 2), privacy: .public) s")
            } catch {
                Self.logger.error("Core ML load failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func forget(_ conversationID: UUID) {
        let core = core
        core.queue.async { core.forget(conversationID) }
    }

    func forgetAll() {
        let core = core
        core.queue.async { core.forgetAll() }
    }

    func reply(to prompt: String, in conversationID: UUID, history: [ChatTurn], options: TextOptions) -> AsyncThrowingStream<String, Error> {
        let core = core
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
                    var sampler = CoreMLSampler()
                    let metrics = try core.generate(
                        conversation: conversationID,
                        turns: turns,
                        prefix: LFMPrompt.prefix(),
                        full: full,
                        next: next,
                        maxTokens: maxTokens,
                        sampler: &sampler,
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
                    Self.logger.notice("Core ML metrics: \(metrics.summary, privacy: .public)")
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
    func loaded() async -> Bool {
        guard isAvailable else { return false }
        let core = core
        return await withCheckedContinuation { continuation in
            core.queue.async {
                do {
                    try core.warm(prefix: LFMPrompt.prefix())
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    func complete(system: String, history: [ChatTurn], prompt: String, seed: UInt64? = nil) async throws -> (String, EngineMetrics) {
        let core = core
        let full = LFMPrompt.text(system: system, history: history, prompt: prompt, thinking: false)
        let turns = history.count
        return try await withCheckedThrowingContinuation { continuation in
            core.queue.async {
                do {
                    var raw = ""
                    var sampler = seed.map { CoreMLSampler(seed: $0) } ?? CoreMLSampler()
                    let metrics = try core.generate(conversation: UUID(), turns: turns, prefix: LFMPrompt.prefix(system: system), full: full, next: "", maxTokens: LFMPrompt.replyTokens, sampler: &sampler, isCancelled: { false }) { raw = $0 }
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
        let core = core
        core.queue.async {
            guard core.isLoaded else { return }
            core.unload()
            Self.logger.notice("Core ML parts unloaded: \(reason, privacy: .public)")
        }
    }
}
