#if DEBUG
import Foundation
import os
import UIKit

enum DebugEval {
    private struct Message: Decodable {
        let role: String
        let content: String
    }

    private struct Item: Decodable {
        let id: String
        let kind: String
        let lang: String
        let messages: [Message]
    }

    private struct Record: Encodable {
        let id: String
        let kind: String
        let lang: String
        let reply: String
        let total_s: Double
        let prompt_tokens: Int
        let generated_tokens: Int
        let first_token_s: Double?
        let decode_tps: Double
        let footprint_mb: Int
        let peak_mb: Int
        let thermal: String
        let error: String?
        let weights: String
        let device: String
    }

    private static let logger = Logger(subsystem: "QuietGPT", category: "eval")

    static func run(sets: [String]) async {
        let engine = LlamaTextEngine(weights: TextEngineKind.weights)
        engine.prepare()
        while engine.store.state != .ready {
            if case .failed(let reason) = engine.store.state {
                logger.error("Eval stopped: \(reason, privacy: .public)")
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        let documents = URL.documentsDirectory
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        let label = engine.store.weights.name.contains("Q4") ? "q4" : "q8"
        for name in sets {
            let source = documents.appending(path: "eval-\(name).json")
            guard let data = try? Data(contentsOf: source), let items = try? JSONDecoder().decode([Item].self, from: data) else {
                logger.error("Eval set missing: \(name, privacy: .public)")
                continue
            }
            var lines = Data()
            for (index, item) in items.enumerated() {
                let system = item.messages.first?.content ?? ""
                let history = item.messages.dropFirst().dropLast().map { ChatTurn(role: $0.role == "user" ? .user : .assistant, text: $0.content) }
                let prompt = item.messages.last?.content ?? ""
                let started = Date()
                var reply = ""
                var metrics = LlamaMetrics()
                var failure: String?
                do {
                    (reply, metrics) = try await engine.complete(system: system, history: history, prompt: prompt)
                } catch {
                    failure = String(describing: error)
                }
                let record = Record(
                    id: item.id,
                    kind: item.kind,
                    lang: item.lang,
                    reply: reply,
                    total_s: Date().timeIntervalSince(started),
                    prompt_tokens: metrics.promptTokens,
                    generated_tokens: metrics.generatedTokens,
                    first_token_s: metrics.firstTokenSeconds,
                    decode_tps: metrics.decodeSeconds > 0 ? Double(metrics.generatedTokens) / metrics.decodeSeconds : 0,
                    footprint_mb: metrics.footprintMB,
                    peak_mb: metrics.peakMB,
                    thermal: metrics.thermal,
                    error: failure,
                    weights: engine.store.weights.name,
                    device: deviceName()
                )
                if let line = try? encoder.encode(record) {
                    lines.append(line)
                    lines.append(Data("\n".utf8))
                    try? lines.write(to: documents.appending(path: "lfm-iphone-\(label)-\(name).jsonl"))
                }
                logger.notice("Eval \(name, privacy: .public) \(index + 1)/\(items.count) \(item.id, privacy: .public): \(metrics.summary, privacy: .public)")
            }
        }
        try? Data("done".utf8).write(to: documents.appending(path: "eval-done.txt"))
        logger.notice("Eval done")
    }

    private static func deviceName() -> String {
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return machine + " iOS " + UIDevice.current.systemVersion
    }
}
#endif
