import Foundation

struct ReplyMetrics {
    private let start: ContinuousClock.Instant
    private var firstText: ContinuousClock.Instant?
    private var end: ContinuousClock.Instant?
    private(set) var characters = 0

    init(start: ContinuousClock.Instant = .now) {
        self.start = start
    }

    mutating func received(_ text: String, at instant: ContinuousClock.Instant = .now) {
        if firstText == nil {
            firstText = instant
        }
        characters = text.count
    }

    mutating func finish(at instant: ContinuousClock.Instant = .now) {
        end = instant
    }

    var estimatedTokens: Int {
        Int((Double(characters) / 4).rounded())
    }

    var timeToFirstText: Duration? {
        firstText.map { start.duration(to: $0) }
    }

    var totalTime: Duration? {
        end.map { start.duration(to: $0) }
    }

    var tokensPerSecond: Double? {
        end.flatMap(rate(until:))
    }

    func rate(until instant: ContinuousClock.Instant) -> Double? {
        guard let firstText else { return nil }
        let seconds = firstText.duration(to: instant).seconds
        guard seconds > 0 else { return nil }
        return Double(estimatedTokens) / seconds
    }

    var summary: String {
        let first = timeToFirstText.map { String(format: "%.2f s", $0.seconds) } ?? "-"
        let total = totalTime.map { String(format: "%.2f s", $0.seconds) } ?? "-"
        let rate = tokensPerSecond.map { String(format: "%.0f", $0) } ?? "-"
        return "first text \(first) · total \(total) · \(characters) chars · ≈\(estimatedTokens) tokens · ≈\(rate) tokens/s"
    }
}

extension Duration {
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
