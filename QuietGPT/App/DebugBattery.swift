#if DEBUG
import Foundation
import os
import UIKit

enum DebugBattery {
    private struct Phase: Decodable {
        let engine: String
        let minutes: Double
    }

    private struct Plan: Decodable {
        let phases: [Phase]
        let prompts: [String]
        let minimumBattery: Double
    }

    private struct Record: Encodable {
        let kind: String
        let phase: String
        let elapsed_s: Double
        let battery: Float
        let battery_state: String
        let thermal: String
        let low_power: Bool
        let brightness: Double
        let footprint_mb: Int
        var prompt: String?
        var reply_chars: Int?
        var reply_s: Double?
        var error: String?
    }

    private static let logger = Logger(subsystem: "QuietGPT", category: "battery")

    static var planURL: URL {
        URL.documentsDirectory.appending(path: "battery-test.json")
    }

    static var isPlanned: Bool {
        FileManager.default.fileExists(atPath: planURL.path)
    }

    static func run() async {
        guard let data = try? Data(contentsOf: planURL), let plan = try? JSONDecoder().decode(Plan.self, from: data) else {
            logger.error("Battery test plan missing or invalid")
            return
        }
        try? FileManager.default.moveItem(at: planURL, to: URL.documentsDirectory.appending(path: "battery-test.started.json"))
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let output = URL.documentsDirectory.appending(path: "battery-\(stamp).jsonl")
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        let names = Set(plan.phases.map(\.engine))
        var engines: [String: any TextEngine] = [:]
        if names.contains("lfm3") {
            let llama = LlamaTextEngine(weights: .q8)
            llama.prepare()
            while llama.store.state != .ready {
                if case .failed(let reason) = llama.store.state {
                    logger.error("Battery test stopped: \(reason, privacy: .public)")
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
            engines["lfm3"] = llama
        }
        if names.contains("lfm3-ane") {
            let ane = CoreMLTextEngine()
            guard await ane.loaded() else {
                logger.error("Battery test stopped: Core ML parts did not load")
                return
            }
            engines["lfm3-ane"] = ane
        }
        if names.contains("apple") {
            let apple = AppleTextEngine()
            apple.prepare()
            engines["apple"] = apple
        }

        while device.batteryState == .charging || device.batteryState == .full {
            write(sample(kind: "waiting", phase: "unplug", start: .now), to: output)
            try? await Task.sleep(for: .seconds(10))
        }

        let start = Date()
        var stopped = false
        for phase in plan.phases where !stopped {
            let end = Date().addingTimeInterval(phase.minutes * 60)
            logger.notice("Battery phase \(phase.engine, privacy: .public) for \(phase.minutes) min")
            let engine = engines[phase.engine]
            var conversation = UUID()
            var history: [ChatTurn] = []
            var index = 0
            var lastSample = Date.distantPast
            while Date() < end {
                if device.batteryLevel >= 0, Double(device.batteryLevel) < plan.minimumBattery {
                    write(sample(kind: "stop", phase: phase.engine, start: start), to: output)
                    stopped = true
                    break
                }
                if UIApplication.shared.applicationState != .active {
                    write(sample(kind: "paused", phase: phase.engine, start: start), to: output)
                    try? await Task.sleep(for: .seconds(10))
                    continue
                }
                guard let engine else {
                    write(sample(kind: "sample", phase: phase.engine, start: start), to: output)
                    try? await Task.sleep(for: .seconds(30))
                    continue
                }
                if Date().timeIntervalSince(lastSample) >= 30 {
                    write(sample(kind: "sample", phase: phase.engine, start: start), to: output)
                    lastSample = .now
                }
                let prompt = plan.prompts[index % plan.prompts.count]
                index += 1
                let started = Date()
                var reply = ""
                var failure: String?
                do {
                    for try await text in engine.reply(to: prompt, in: conversation, history: history, options: TextOptions()) {
                        reply = text
                    }
                } catch {
                    failure = String(describing: error)
                }
                var record = sample(kind: "reply", phase: phase.engine, start: start)
                record.prompt = String(prompt.prefix(60))
                record.reply_chars = reply.count
                record.reply_s = Date().timeIntervalSince(started)
                record.error = failure
                write(record, to: output)
                if failure == nil {
                    history.append(ChatTurn(role: .user, text: prompt))
                    history.append(ChatTurn(role: .assistant, text: reply))
                }
                if failure != nil || history.count >= 20 {
                    engine.forget(conversation)
                    conversation = UUID()
                    history = []
                }
            }
            engine?.forgetAll()
        }
        write(sample(kind: "done", phase: "end", start: start), to: output)
        logger.notice("Battery test done")
    }

    private static func sample(kind: String, phase: String, start: Date) -> Record {
        let device = UIDevice.current
        let state = switch device.batteryState {
        case .charging: "charging"
        case .full: "full"
        case .unplugged: "unplugged"
        default: "unknown"
        }
        let brightness = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.brightness ?? -1
        return Record(
            kind: kind,
            phase: phase,
            elapsed_s: Date().timeIntervalSince(start),
            battery: device.batteryLevel,
            battery_state: state,
            thermal: EngineMetrics.thermal(),
            low_power: ProcessInfo.processInfo.isLowPowerModeEnabled,
            brightness: Double(brightness),
            footprint_mb: EngineMetrics.memory().0,
            prompt: nil,
            reply_chars: nil,
            reply_s: nil,
            error: nil
        )
    }

    private static func write(_ record: Record, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        guard var line = try? encoder.encode(record) else { return }
        line.append(Data("\n".utf8))
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }
}
#endif
