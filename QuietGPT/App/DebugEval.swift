#if DEBUG
import Foundation
import FoundationModels
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

    private struct Plan: Decodable {
        let engines: [String]
        let sets: [String]
        let pauseSeconds: Double?
    }

    private struct Stage: Encodable {
        let engine: String
        let started: String
        let seconds: Double
        let battery_start: Float
        let battery_end: Float
        let thermal_end: String
    }

    static var planURL: URL {
        URL.documentsDirectory.appending(path: "eval-plan.json")
    }

    static var isPlanned: Bool {
        FileManager.default.fileExists(atPath: planURL.path)
    }

    static func run(sets: [String]) async {
        let engine: any EvalEngine = TextEngineKind.selected == .lfm3ane ? CoreMLTextEngine() : LlamaTextEngine(weights: TextEngineKind.weights)
        guard await engine.waitUntilReady() else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        for name in sets {
            await run(engine: engine, set: name, source: "eval-\(name).json")
        }
        try? Data("done".utf8).write(to: URL.documentsDirectory.appending(path: "eval-done.txt"))
        logger.notice("Eval done")
    }

    static func runPlan() async {
        guard let data = try? Data(contentsOf: planURL), let plan = try? JSONDecoder().decode(Plan.self, from: data) else {
            logger.error("Eval plan missing or invalid")
            return
        }
        let started = URL.documentsDirectory.appending(path: "eval-plan.started.json")
        try? FileManager.default.removeItem(at: started)
        try? FileManager.default.moveItem(at: planURL, to: started)
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        while device.batteryState == .charging || device.batteryState == .full {
            logger.notice("Eval plan waits for the cable to be removed")
            try? await Task.sleep(for: .seconds(10))
        }
        let stamp = ISO8601DateFormatter()
        let log = URL.documentsDirectory.appending(path: "eval-plan-log.jsonl")
        var lines = (try? Data(contentsOf: log)) ?? Data()
        for (index, name) in plan.engines.enumerated() {
            if index > 0, let pause = plan.pauseSeconds, pause > 0 {
                logger.notice("Eval plan pause \(pause) s")
                try? await Task.sleep(for: .seconds(pause))
            }
            let engine: any EvalEngine
            switch name {
            case "apple": engine = AppleTextEngine()
            case "lfm3": engine = LlamaTextEngine(weights: .q8)
            case "lfm3-ane": engine = CoreMLTextEngine()
            default:
                logger.error("Eval plan engine unknown: \(name, privacy: .public)")
                continue
            }
            guard await engine.waitUntilReady() else { continue }
            let begin = Date()
            let batteryStart = device.batteryLevel
            for set in plan.sets {
                let variant = name == "apple" ? "apple" : "lfm"
                await run(engine: engine, set: set, source: "eval-\(variant)-\(set).json")
            }
            let stage = Stage(engine: name, started: stamp.string(from: begin), seconds: Date().timeIntervalSince(begin), battery_start: batteryStart, battery_end: device.batteryLevel, thermal_end: EngineMetrics.thermal())
            if let line = try? JSONEncoder().encode(stage) {
                lines.append(line)
                lines.append(Data("\n".utf8))
                try? lines.write(to: log)
            }
            engine.evalUnload()
            logger.notice("Eval plan engine done: \(name, privacy: .public)")
        }
        try? Data("done".utf8).write(to: URL.documentsDirectory.appending(path: "eval-done.txt"))
        logger.notice("Eval done")
    }

    private static func run(engine: any EvalEngine, set name: String, source: String) async {
        let documents = URL.documentsDirectory
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        let label = engine.evalLabel
        guard let data = try? Data(contentsOf: documents.appending(path: source)), let items = try? JSONDecoder().decode([Item].self, from: data) else {
            logger.error("Eval set missing: \(source, privacy: .public)")
            return
        }
        var lines = Data()
        for (index, item) in items.enumerated() {
            let system = item.messages.first?.content ?? ""
            let history = item.messages.dropFirst().dropLast().map { ChatTurn(role: $0.role == "user" ? .user : .assistant, text: $0.content) }
            let prompt = item.messages.last?.content ?? ""
            let started = Date()
            var reply = ""
            var metrics = EngineMetrics()
            var failure: String?
            do {
                (reply, metrics) = try await engine.complete(system: system, history: history, prompt: prompt, kind: item.kind)
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
                weights: engine.evalWeights,
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

    fileprivate static func stop(_ reason: String) {
        logger.error("Eval stopped: \(reason, privacy: .public)")
    }

    private static func deviceName() -> String {
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return machine + " iOS " + UIDevice.current.systemVersion
    }
}

@MainActor
private protocol EvalEngine {
    var evalLabel: String { get }
    var evalWeights: String { get }
    func waitUntilReady() async -> Bool
    func complete(system: String, history: [ChatTurn], prompt: String, kind: String) async throws -> (String, EngineMetrics)
    func evalUnload()
}

extension LlamaTextEngine: EvalEngine {
    var evalLabel: String {
        store.weights.name.contains("Q4") ? "q4" : "q8"
    }

    var evalWeights: String {
        store.weights.name
    }

    func waitUntilReady() async -> Bool {
        prepare()
        while store.state != .ready {
            if case .failed(let reason) = store.state {
                DebugEval.stop(reason)
                return false
            }
            try? await Task.sleep(for: .seconds(1))
        }
        return true
    }

    func complete(system: String, history: [ChatTurn], prompt: String, kind: String) async throws -> (String, EngineMetrics) {
        try await complete(system: system, history: history, prompt: prompt)
    }
}

extension AppleTextEngine: EvalEngine {
    var evalLabel: String {
        "apple"
    }

    var evalWeights: String {
        "system"
    }

    func waitUntilReady() async -> Bool {
        for _ in 0..<60 where !isAvailable {
            try? await Task.sleep(for: .seconds(1))
        }
        guard isAvailable else {
            DebugEval.stop("Apple Intelligence not available")
            return false
        }
        prepare()
        return true
    }

    func complete(system: String, history: [ChatTurn], prompt: String, kind: String) async throws -> (String, EngineMetrics) {
        var instructions = system
        if !history.isEmpty {
            let recap = history.map { "\($0.role == .user ? "User" : "QuietGPT"): \($0.text.prefix(600))" }.joined(separator: "\n")
            instructions += "\n\nThe conversation so far:\n" + recap
        }
        let session = kind == "rewrite"
            ? LanguageModelSession(model: SystemLanguageModel(guardrails: .permissiveContentTransformations), instructions: instructions)
            : LanguageModelSession(instructions: instructions)
        var metrics = EngineMetrics()
        let started = Date()
        var reply = ""
        do {
            for try await snapshot in session.streamResponse(to: prompt) {
                if metrics.firstTokenSeconds == nil, !snapshot.content.isEmpty {
                    metrics.firstTokenSeconds = Date().timeIntervalSince(started)
                }
                reply = snapshot.content
            }
        } catch {
            throw Self.translate(error)
        }
        metrics.decodeSeconds = Date().timeIntervalSince(started) - (metrics.firstTokenSeconds ?? 0)
        (metrics.footprintMB, metrics.peakMB) = EngineMetrics.memory()
        metrics.thermal = EngineMetrics.thermal()
        return (reply, metrics)
    }

    func evalUnload() {
        forgetAll()
    }
}

extension CoreMLTextEngine: EvalEngine {
    var evalLabel: String {
        "ane-lut8"
    }

    var evalWeights: String {
        Self.bundleName
    }

    func waitUntilReady() async -> Bool {
        guard isAvailable else {
            DebugEval.stop("Core ML bundle missing")
            return false
        }
        return true
    }

    func complete(system: String, history: [ChatTurn], prompt: String, kind: String) async throws -> (String, EngineMetrics) {
        try await complete(system: system, history: history, prompt: prompt, seed: nil)
    }
}
#endif
