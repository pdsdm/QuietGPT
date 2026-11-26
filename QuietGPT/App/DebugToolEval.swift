#if DEBUG
import Foundation
import os

struct MockToolData: Decodable, Sendable {
    struct Now: Decodable, Sendable {
        let date: String
        let weekday: String
        let time: String
    }

    struct Event: Decodable, Sendable {
        let date: String
        let time: String
        let minutes: Int
        let title: String
    }

    struct Contact: Decodable, Sendable {
        let name: String
        let phone: String
    }

    struct Note: Decodable, Sendable {
        let title: String
        let body: String
    }

    struct Message: Decodable, Sendable {
        let from: String
        let time: String
        let text: String
    }

    let now: Now
    let events: [Event]
    let contacts: [Contact]
    let notes: [Note]
    let inbox: [Message]?
}

struct MockTools {
    static let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static let dayWords: [[String]] = [
        ["monday", "lunes", "dilluns"], ["tuesday", "martes", "dimarts"], ["wednesday", "miercoles", "dimecres"],
        ["thursday", "jueves", "dijous"], ["friday", "viernes", "divendres"], ["saturday", "sabado", "dissabte"],
        ["sunday", "domingo", "diumenge"],
    ]

    let data: MockToolData

    func run(_ name: String, _ args: [String: String]) -> String {
        switch name {
        case "get_current_datetime":
            return json(["date": data.now.date, "time": data.now.time, "weekday": data.now.weekday])
        case "date_resolve":
            return resolve(args["text"] ?? "")
        case "clock_add":
            guard let time = Self.minutes(args["time"] ?? ""), let add = Int(args["minutes"] ?? "0") else { return "Use time as HH:MM and minutes as a number" }
            return Self.clock(time + add)
        case "calendar_free_slots":
            return freeSlots(args)
        case "calendar_find_event":
            let words = words(args["text"] ?? "")
            let day = args["date"] ?? ""
            let found = data.events.filter { e in (day.isEmpty || e.date == day) && words.contains { Self.fold(e.title).contains($0) } }
            return found.isEmpty ? "No event matches." : found.map(line).joined(separator: "\n")
        case "calendar_list_events":
            let first = args["date"] ?? ""
            let last = args["end_date"].flatMap { $0.isEmpty ? nil : $0 } ?? first
            guard Self.date(first) != nil, Self.date(last) != nil else { return "Use the date as YYYY-MM-DD." }
            let label = first == last ? Self.label(first) : "\(Self.label(first)) to \(Self.label(last))"
            let found = data.events.filter { $0.date >= first && $0.date <= last }
            return found.isEmpty ? "No events on \(label)." : found.map(line).joined(separator: "\n")
        case "calendar_create_event":
            return "Done: event \"\(args["title"] ?? "")\" created on \(args["date"] ?? "") at \(args["time"] ?? "") for \(args["minutes"] ?? "") minutes"
        case "reminders_create":
            return "Done: reminder \"\(args["text"] ?? "")\" set for \(args["date"] ?? "") at \(args["time"] ?? "")"
        case "timer_start":
            return "Done: timer started for \(args["minutes"] ?? "") minutes"
        case "messages_send":
            return "Done: message sent to \(args["to"] ?? ""): \"\(args["text"] ?? "")\""
        case "messages_read":
            let lines = (data.inbox ?? []).enumerated().map { "\($0.offset + 1). From \($0.element.from) at \($0.element.time): \($0.element.text)" }
            return lines.isEmpty ? "No messages." : lines.joined(separator: "\n")
        case "notes_search":
            let found = notes(matching: words(args["query"] ?? ""))
            return found.isEmpty ? "No note matches." : found.map { "Note \"\($0.title)\": \($0.body)" }.joined(separator: "\n")
        case "contacts_find":
            return contacts(args["name"] ?? "")
        case "calculator":
            guard let value = Self.calculate(args["expression"] ?? "") else { return json(["error": "Use only numbers, + - * / and parentheses"]) }
            return json(["result": Self.number(value)])
        default:
            return json(["error": "unknown tool \(name)"])
        }
    }

    private func contacts(_ name: String) -> String {
        let query = Self.fold(name)
        let matches = data.contacts.filter { !query.isEmpty && Self.fold($0.name).contains(query) }
        let lines = matches.map { "\($0.name), \($0.phone)" }
        if matches.count > 1 {
            return lines.joined(separator: "\n") + "\nMore than one contact matches. Ask the user which one, and do not act yet."
        }
        if matches.isEmpty {
            return "No contact matches." + notes(matching: words(name)).map { "\nNote \"\($0.title)\": \($0.body)" }.joined()
        }
        return lines.joined(separator: "\n")
    }

    private func freeSlots(_ args: [String: String]) -> String {
        let day = args["date"] ?? ""
        guard var cursor = Self.minutes(args["after"] ?? "00:00"), let end = Self.minutes(args["before"] ?? "23:59"), let need = Int(args["minutes"] ?? "30") else {
            return "Use date YYYY-MM-DD, times HH:MM and minutes as a number"
        }
        var lines: [String] = []
        for e in data.events.filter({ $0.date == day }).sorted(by: { $0.time < $1.time }) {
            let start = Self.minutes(e.time) ?? 0
            let stop = start + e.minutes
            if stop <= cursor || start >= end { continue }
            if start - cursor >= need { lines.append("Free from \(Self.clock(cursor)) to \(Self.clock(start))") }
            cursor = max(cursor, stop)
        }
        if end - cursor >= need { lines.append("Free from \(Self.clock(cursor)) to \(Self.clock(end))") }
        return lines.isEmpty ? "No free time in that range." : lines.joined(separator: "\n")
    }

    private func resolve(_ input: String) -> String {
        let failure = "Write a day word such as tomorrow, Monday or next week"
        guard let today = Self.date(data.now.date) else { return failure }
        let folded = Self.fold(input)
        let tokens = Set(folded.split(separator: " ").map(String.init))
        func has(_ phrases: [String]) -> Bool { phrases.contains { folded.contains($0) } }
        func add(_ days: Int) -> Date { Self.calendar.date(byAdding: .day, value: days, to: today)! }
        let weekday = Self.weekday(today)
        var day: Date?
        if let range = input.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            day = Self.date(String(input[range]))
        } else if has(["day after tomorrow", "pasado manana", "dema passat"]) {
            day = add(2)
        } else if has(["tomorrow", "manana", "dema"]) {
            day = add(1)
        } else if has(["today", "hoy", "avui", "tonight", "esta noche", "aquesta nit"]) {
            day = today
        } else if has(["next week", "proxima semana", "semana que viene", "setmana que ve", "propera setmana"]) {
            day = add(7 - weekday)
        } else if has(["weekend", "fin de semana", "cap de setmana"]) {
            let offset = (5 - weekday + 7) % 7
            day = add(offset == 0 ? 7 : offset)
        } else if let index = Self.dayWords.firstIndex(where: { $0.contains { tokens.contains($0) } }) {
            let offset = (index - weekday + 7) % 7
            day = add(offset == 0 ? 7 : offset)
        }
        guard let day else { return failure }
        return "\(Self.names[Self.weekday(day)]) \(Self.text(day))"
    }

    private func notes(matching words: [String]) -> [MockToolData.Note] {
        data.notes.filter { note in words.contains { Self.fold(note.title + " " + note.body).contains($0) } }
    }

    private func words(_ text: String) -> [String] {
        Self.fold(text).split(separator: " ").map(String.init).filter { $0.count >= 3 }
    }

    private func line(_ e: MockToolData.Event) -> String {
        "\(Self.label(e.date)), \(e.time) to \(Self.clock((Self.minutes(e.time) ?? 0) + e.minutes)): \(e.title)"
    }

    private func json(_ value: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func date(_ text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func text(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func weekday(_ date: Date) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    static func label(_ day: String) -> String {
        guard let date = date(day) else { return day }
        return "\(names[weekday(date)]) \(day)"
    }

    static func minutes(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    static func clock(_ total: Int) -> String {
        let value = ((total % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    static func fold(_ text: String) -> String {
        let plain = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil).lowercased()
        return String(plain.unicodeScalars.filter { ($0.value >= 97 && $0.value <= 122) || ($0.value >= 48 && $0.value <= 57) || $0 == " " }.map(Character.init))
    }

    static func number(_ value: Double) -> String {
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    static func calculate(_ text: String) -> Double? {
        var parser = Parser(text)
        guard let value = parser.expression(), parser.index == parser.chars.count else { return nil }
        return value
    }

    private struct Parser {
        let chars: [Character]
        var index = 0

        init(_ text: String) {
            chars = Array(text.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "x", with: "*").replacingOccurrences(of: "×", with: "*").filter { $0 != " " })
        }

        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while index < chars.count, chars[index] == "+" || chars[index] == "-" {
                let op = chars[index]
                index += 1
                guard let right = term() else { return nil }
                value = op == "+" ? value + right : value - right
            }
            return value
        }

        mutating func term() -> Double? {
            guard var value = factor() else { return nil }
            while index < chars.count, chars[index] == "*" || chars[index] == "/" {
                let op = chars[index]
                index += 1
                guard let right = factor() else { return nil }
                value = op == "*" ? value * right : value / right
            }
            return value
        }

        mutating func factor() -> Double? {
            guard index < chars.count else { return nil }
            if chars[index] == "-" {
                index += 1
                return factor().map { -$0 }
            }
            if chars[index] == "(" {
                index += 1
                let value = expression()
                guard index < chars.count, chars[index] == ")" else { return nil }
                index += 1
                return value
            }
            let start = index
            while index < chars.count, chars[index].isNumber || chars[index] == "." { index += 1 }
            return Double(String(chars[start..<index]))
        }
    }
}

enum DebugToolEval {
    struct Spec: Decodable {
        struct Task: Decodable {
            let id: String
            let text: String
        }

        let system: String
        let data: MockToolData
        let maxRounds: Int
        let callLimit: Int
        let taskSeconds: Double?
        let tasks: [Task]
    }

    struct Call: Encodable {
        let tool: String
        let args: [String: String]
        let result: String
    }

    struct Record: Encodable {
        let id: String
        let calls: [Call]
        let reply: String
        let rounds: Int
        let total_s: Double
        let prefill_s: Double
        let prompt_tokens: Int
        let generated_tokens: Int
        let reused_tokens: Int
        let thought_chars: Int
        let thermal: String
        let error: String?
    }

    private static let logger = Logger(subsystem: "QuietGPT", category: "eval")
    private static func note(_ line: String, to url: URL) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private static let limitText = "{\"error\":\"Tool limit reached. Do not call more tools. Reply to the user now.\"}"

    @MainActor
    static func run(engine: CoreMLTextEngine, spec: Spec, thinking: Bool, output: URL, tune: @escaping (inout CoreMLSampler) -> Void) async {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        let tools = MockTools(data: spec.data)
        let progress = URL.documentsDirectory.appending(path: "tool-eval-progress.log")
        var lines = Data()
        let warming = Date()
        let warm = await engine.warmAll()
        note("\(Date().formatted(date: .omitted, time: .standard)) larger contexts ready: \(warm) after \(Int(Date().timeIntervalSince(warming))) s", to: progress)
        for (index, task) in spec.tasks.enumerated() {
            let conversation = UUID()
            var full = LFMPrompt.text(system: spec.system, history: [], prompt: task.text, thinking: thinking)
            var next = ""
            var calls: [Call] = []
            var reply = "(stopped after the round limit)"
            var rounds = 0
            var prefill = 0.0
            var promptTokens = 0
            var generated = 0
            var reused = 0
            var thought = 0
            var thermal = ""
            var failure: String?
            let started = Date()
            let deadline = started.addingTimeInterval(spec.taskSeconds ?? 300)
            do {
                for round in 0..<spec.maxRounds {
                    note("\(Date().formatted(date: .omitted, time: .standard)) \(task.id) round \(round + 1) start", to: progress)
                    let (raw, metrics) = try await engine.toolRound(conversation: conversation, round: round, system: spec.system, full: full, next: next, thinking: thinking, deadline: deadline, tune: tune)
                    note("\(Date().formatted(date: .omitted, time: .standard)) \(task.id) round \(round + 1) prompt \(metrics.promptTokens) generated \(metrics.generatedTokens) context \(metrics.context) prefill \(String(format: "%.1f", metrics.prefillSeconds)) s thermal \(metrics.thermal)", to: progress)
                    if Date() > deadline {
                        failure = "time limit"
                        reply = LFMPrompt.answer(raw)
                        break
                    }
                    rounds = round + 1
                    prefill += metrics.prefillSeconds
                    promptTokens = metrics.promptTokens
                    generated += metrics.generatedTokens
                    reused += metrics.reusedTokens
                    thermal = metrics.thermal
                    if thinking { thought += LFMPrompt.thought(raw).count }
                    let found = LFMPrompt.toolCalls(in: raw)
                    guard !found.isEmpty else {
                        reply = LFMPrompt.answer(raw)
                        break
                    }
                    var results: [String] = []
                    for call in found {
                        let result = calls.count >= spec.callLimit ? limitText : tools.run(call.name, call.arguments)
                        calls.append(Call(tool: call.name, args: call.arguments, result: result))
                        results.append(result)
                    }
                    next = LFMPrompt.toolResults(results, thinking: thinking)
                    full += raw + next
                }
            } catch {
                failure = String(describing: error)
            }
            let record = Record(id: task.id, calls: calls, reply: reply, rounds: rounds, total_s: Date().timeIntervalSince(started), prefill_s: prefill, prompt_tokens: promptTokens, generated_tokens: generated, reused_tokens: reused, thought_chars: thought, thermal: thermal, error: failure)
            if let line = try? encoder.encode(record) {
                lines.append(line)
                lines.append(Data("\n".utf8))
                try? lines.write(to: output)
            }
            logger.notice("Tool eval \(index + 1)/\(spec.tasks.count) \(task.id, privacy: .public): \(calls.count) calls, \(rounds) rounds, \(record.total_s, format: .fixed(precision: 1)) s")
        }
    }
}
#endif
