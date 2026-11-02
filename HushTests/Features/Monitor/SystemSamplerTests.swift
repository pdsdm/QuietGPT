import Testing
@testable import Hush

@MainActor
struct SystemSamplerTests {
    @Test func readsMemoryAndCPU() {
        let sampler = SystemSampler()
        _ = sampler.read()
        let reading = sampler.read(at: .now.advanced(by: .seconds(1)))
        #expect((reading.memoryBytes ?? 0) > 0)
        #expect(reading.appCPU != nil)
    }
}
