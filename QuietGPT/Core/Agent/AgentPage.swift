import Foundation

struct PageElement: Codable, Equatable {
    var id: Int
    var kind: String
    var type: String
    var label: String
    var value: String
    var options: [String]
    var secret: Bool

    private static let finalWords = [
        "reserve", "reservation", "book", "confirm", "pay", "purchase", "buy", "order", "checkout", "complete", "send", "submit",
        "reservar", "reserva", "confirmar", "pagar", "comprar", "pedir", "finalizar", "enviar"
    ]

    var name: String {
        label.isEmpty ? kind : label
    }

    var needsApproval: Bool {
        guard kind == "button" || kind == "link" else { return false }
        let words = label.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        return words.contains { Self.finalWords.contains($0) }
    }

    var line: String {
        var text = "[\(id)] \(kind)"
        if kind == "field", !type.isEmpty, type != "text" {
            text += "(\(type))"
        }
        text += " \"\(label)\""
        if !value.isEmpty {
            text += " = \"\(value)\""
        }
        if !options.isEmpty {
            text += " options: " + options.joined(separator: " | ")
        }
        return text
    }
}

struct PageSnapshot: Codable, Equatable {
    var title: String
    var url: String
    var text: String
    var elements: [PageElement]

    var host: String {
        URL(string: url)?.host() ?? ""
    }

    func element(_ id: Int) -> PageElement? {
        elements.first { $0.id == id }
    }
}

enum AgentAction: Equatable {
    case tap(Int)
    case type(Int, String)
    case select(Int, String)
    case scroll
    case finish(String)
    case stop(String)
}

struct AgentDecision: Equatable {
    var action: AgentAction
    var reason: String
}

enum AgentPrompt {
    static let instructions = """
    You control a web page for the user, one step at a time. \
    Choose the one next step that moves the task forward. \
    Use only the element numbers from the list. \
    Use type for a field, select for a list, tap for a button, a link or a check. \
    Use scroll when the element you need is not in the list. \
    Use finish when the page shows that the task is complete. \
    Use stop when you cannot continue, or when the page needs a login, a code or a payment. \
    Do not repeat a step that is already done. \
    Never invent a name, a phone number or an email address.
    """

    static func text(task: String, page: PageSnapshot, done: [String], today: Date = .now, elementLimit: Int = 60, includesText: Bool = true) -> String {
        var parts = ["Task: \(task)", "Today: \(today.formatted(.iso8601.year().month().day())), \(today.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "en_US"))))"]
        parts.append("Page: \(page.title) (\(page.host))")
        if includesText, !page.text.isEmpty {
            parts.append("Page text: \(page.text)")
        }
        if !done.isEmpty {
            parts.append("Steps done:\n" + done.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        }
        parts.append("Elements:\n" + page.elements.prefix(elementLimit).map(\.line).joined(separator: "\n"))
        return parts.joined(separator: "\n\n")
    }

    static func summary(of action: AgentAction, on page: PageSnapshot) -> String {
        switch action {
        case .tap(let id):
            "tap [\(id)] \"\(page.element(id)?.name ?? "")\""
        case .type(let id, let text):
            "type \"\(text)\" in [\(id)] \"\(page.element(id)?.name ?? "")\""
        case .select(let id, let option):
            "select \"\(option)\" in [\(id)] \"\(page.element(id)?.name ?? "")\""
        case .scroll:
            "scroll"
        case .finish(let message):
            "finish: \(message)"
        case .stop(let message):
            "stop: \(message)"
        }
    }
}
