#if DEBUG
import Foundation
import os

enum DebugLongChat {
    private static let logger = Logger(subsystem: "QuietGPT", category: "longchat")

    private static let prompts = [
        "I want to plan a garden for a small backyard in a dry, hot climate. Describe in detail which plants I can use, how to water them, and how to lay out the space.",
        "Now write a month by month calendar for the first year, with the tasks for each month.",
        "Which of these plants are safe for dogs? Give me the full list again with a note for each one.",
        "Write a short guide for my neighbor, who will water the garden while I travel for three weeks in August.",
        "Explain how to build a simple drip irrigation system with a timer, step by step, with a list of parts.",
        "What mistakes do beginners make with this kind of garden? Give me at least ten, with a fix for each.",
        "Write a short text for a sign at the garden gate that explains the idea of the garden to visitors.",
        "Make a shopping list for the whole project, grouped by store type, with rough prices.",
        "Summarize everything we planned in this chat in one page that I can print.",
        "Which three things should I do this weekend to start?",
        "Write a friendly message to my family to invite them to help on the first planting day.",
        "Give me a checklist for the first planting day, from the morning to the evening.",
    ]

    static func run() async {
        let engine = CoreMLTextEngine()
        guard await engine.loaded() else {
            logger.error("Long chat stopped: Core ML parts did not load")
            return
        }
        let conversation = UUID()
        var history: [ChatTurn] = []
        for (index, prompt) in prompts.enumerated() {
            let started = Date()
            var first: Double?
            var reply = ""
            do {
                for try await text in engine.reply(to: prompt, in: conversation, history: history, options: TextOptions()) {
                    if first == nil { first = Date().timeIntervalSince(started) }
                    reply = text
                }
            } catch {
                logger.error("Long chat turn \(index + 1) failed: \(String(describing: error), privacy: .public)")
                return
            }
            let seconds = Date().timeIntervalSince(started)
            logger.notice("Long chat turn \(index + 1): first text \(first ?? 0, format: .fixed(precision: 2), privacy: .public) s, total \(seconds, format: .fixed(precision: 1), privacy: .public) s, \(reply.count) characters")
            history += [ChatTurn(role: .user, text: prompt), ChatTurn(role: .assistant, text: reply)]
        }
        logger.notice("Long chat done")
    }
}
#endif
