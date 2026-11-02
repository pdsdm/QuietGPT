import Testing
@testable import Hush

struct ReplyMetricsTests {
    @Test func measuresFirstTextTotalAndRate() {
        let start = ContinuousClock.now
        var metrics = ReplyMetrics(start: start)
        metrics.received("Hi", at: start.advanced(by: .milliseconds(500)))
        metrics.received(String(repeating: "a", count: 400), at: start.advanced(by: .seconds(2)))
        metrics.finish(at: start.advanced(by: .milliseconds(2500)))

        #expect(metrics.timeToFirstText == .milliseconds(500))
        #expect(metrics.totalTime == .milliseconds(2500))
        #expect(metrics.characters == 400)
        #expect(metrics.estimatedTokens == 100)
        #expect(metrics.tokensPerSecond == 50)
    }

    @Test func hasNoRateBeforeFinish() {
        var metrics = ReplyMetrics()
        metrics.received("Hello")
        #expect(metrics.tokensPerSecond == nil)
        #expect(metrics.totalTime == nil)
    }
}
