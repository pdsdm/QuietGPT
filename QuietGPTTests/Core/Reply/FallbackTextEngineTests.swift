import Foundation
import Testing
@testable import QuietGPT

@MainActor
struct FallbackTextEngineTests {
    private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var last = ""
        for try await text in stream {
            last = text
        }
        return last
    }

    private func engines(main readiness: TextReadiness, fallbackAvailable: Bool = true) -> (FakeTextEngine, FakeTextEngine, FallbackTextEngine) {
        let main = FakeTextEngine([.success("main")])
        main.readiness = readiness
        main.supportsThinking = true
        let fallback = FakeTextEngine([.success("fallback")])
        fallback.isAvailable = fallbackAvailable
        return (main, fallback, FallbackTextEngine(main: main, fallback: fallback))
    }

    @Test func usesTheMainEngineWhenReady() async throws {
        let (_, fallback, engine) = engines(main: .ready)
        #expect(try await collect(engine.reply(to: "Hi", in: UUID(), history: [], options: TextOptions())) == "main")
        #expect(engine.supportsThinking)
        engine.prepare()
        #expect(fallback.prepared == 0)
    }

    @Test func waitsForTheMainEngineWhileItLoads() async throws {
        let (_, _, engine) = engines(main: .loading)
        #expect(engine.readiness == .loading)
        #expect(try await collect(engine.reply(to: "Hi", in: UUID(), history: [], options: TextOptions())) == "main")
    }

    @Test func usesTheFallbackDuringFirstSetup() async throws {
        let (main, fallback, engine) = engines(main: .setup)
        #expect(engine.readiness == .ready)
        #expect(!engine.supportsThinking)
        engine.prepare()
        #expect(main.prepared == 1 && fallback.prepared == 1)
        #expect(try await collect(engine.reply(to: "Hi", in: UUID(), history: [], options: TextOptions())) == "fallback")
    }

    @Test func waitsForSetupWithoutAFallback() async throws {
        let (_, _, engine) = engines(main: .setup, fallbackAvailable: false)
        #expect(engine.readiness == .setup)
        #expect(try await collect(engine.reply(to: "Hi", in: UUID(), history: [], options: TextOptions())) == "main")
    }

    @Test func usesTheFallbackWhenTheMainEngineIsMissing() async throws {
        let (main, _, engine) = engines(main: .ready)
        main.isAvailable = false
        #expect(engine.isAvailable)
        #expect(try await collect(engine.reply(to: "Hi", in: UUID(), history: [], options: TextOptions())) == "fallback")
    }

    @Test func forgetsInBothEngines() {
        let (main, fallback, engine) = engines(main: .ready)
        let id = UUID()
        engine.forget(id)
        #expect(main.forgotten == [id] && fallback.forgotten == [id])
    }
}
