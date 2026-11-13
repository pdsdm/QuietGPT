import Foundation

nonisolated enum LFMPrompt {
    static let instructions = """
    You are QuietGPT, a private assistant on the user's iPhone. Nothing the user writes leaves the device.

    Rules:
    1. Reply in the language of the user's last message.
    2. Start with the answer. No intro such as "Here is" or "Sure".
    3. Follow format requests exactly. "Yes or no" means one word. "One sentence" means one sentence.
    4. When you write a message, email or letter for the user, write it as the user, ready to send. Never use brackets or placeholders such as [Name]. If you do not know a name, leave it out. Do not sign it, and never sign as QuietGPT.
    5. End when the answer ends. No question at the end, and no offer such as "Let me know".
    6. If you are not sure of a fact, a number, a law or a date, say that you are not sure. Never invent one.
    7. For medicines, health and law, give the standard safe answer, then say to check with a doctor, a pharmacist or a lawyer.
    8. If the user asks what you are or who made you, say: "I'm QuietGPT, a private assistant that runs on your iPhone." Never name a company, a lab or the technology behind you.
    """

    static let replyTokens = 700
    static let thinkingTokens = 2000

    private static let lineSignature = try! NSRegularExpression(pattern: #"\n[ \t]*QuietGPT( on your iPhone)?[ \t]*\.?[ \t]*(?=\n|$)"#)
    private static let endSignature = try! NSRegularExpression(pattern: #"([,.!])?[ \t]*QuietGPT\s*\.?\s*$"#)
    private static let sentenceBreak = try! NSRegularExpression(pattern: #"(?<=[.!?])\s+"#)
    private static let offer = try! NSRegularExpression(
        pattern: #"(let me know|anything else|would you like|do you want|want me to|need (any )?(more )?help|how can i help|can i help|shall i|quieres|necesitas|te gustaría|puedo ayudarte|vols|t'ajudo|souhaitez|möchtest|vuoi|quer)"#,
        options: .caseInsensitive
    )

    static func text(system: String = instructions, history: [ChatTurn], prompt: String, thinking: Bool) -> String {
        var text = "<|startoftext|>" + block("system", system)
        for turn in history {
            switch turn.role {
            case .user:
                text += block("user", turn.text)
            case .assistant:
                text += block("assistant", "<think></think>" + turn.text)
            }
        }
        return text + block("user", prompt) + opening(thinking: thinking)
    }

    static func next(prompt: String, thinking: Bool) -> String {
        "<|im_end|>\n" + block("user", prompt) + opening(thinking: thinking)
    }

    static func clean(_ reply: String, thinking: Bool, final: Bool) -> String {
        let text: String
        if let end = reply.range(of: "</think>", options: .backwards) {
            text = String(reply[end.upperBound...])
        } else if thinking {
            return ""
        } else {
            text = reply
        }
        var result = text.replacingOccurrences(of: "<think>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        result = replace(lineSignature, in: result, with: "")
        guard final else { return result }
        result = replace(endSignature, in: result, with: "$1")
        while result.last?.isWhitespace == true {
            result.removeLast()
        }
        return withoutOffer(result)
    }

    private static func opening(thinking: Bool) -> String {
        "<|im_start|>assistant\n" + (thinking ? "<think>" : "<think></think>")
    }

    private static func block(_ role: String, _ content: String) -> String {
        "<|im_start|>\(role)\n\(content)<|im_end|>\n"
    }

    private static func replace(_ pattern: NSRegularExpression, in text: String, with template: String) -> String {
        pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func withoutOffer(_ text: String) -> String {
        var paragraphs = text.components(separatedBy: "\n\n")
        guard let last = paragraphs.last?.trimmingCharacters(in: .whitespacesAndNewlines) else { return text }
        var parts = split(last)
        guard let closing = parts.last,
              closing.range(of: #"\?\W*$"#, options: .regularExpression) != nil,
              offer.firstMatch(in: closing, range: NSRange(closing.startIndex..., in: closing)) != nil
        else { return text }
        parts.removeLast()
        if !parts.isEmpty {
            paragraphs[paragraphs.count - 1] = parts.joined(separator: " ")
        } else if paragraphs.count > 1 {
            paragraphs.removeLast()
        }
        return paragraphs.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func split(_ text: String) -> [String] {
        var parts: [String] = []
        var start = text.startIndex
        for match in sentenceBreak.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            parts.append(String(text[start..<range.lowerBound]))
            start = range.upperBound
        }
        parts.append(String(text[start...]))
        return parts
    }
}
