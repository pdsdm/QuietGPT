import Foundation
import Testing
@testable import QuietGPT

struct CoreMLMathTests {
    @Test func promptsOfWholeBlocksUseOnlyPrefillPasses() {
        #expect(CoreMLMath.passes(count: 64, prefill: 64) == [64])
        #expect(CoreMLMath.passes(count: 128, prefill: 64) == [64, 64])
    }

    @Test func theRestOfAPromptUsesDecodePasses() {
        #expect(CoreMLMath.passes(count: 130, prefill: 64) == [64, 64, 1, 1])
        #expect(CoreMLMath.passes(count: 3, prefill: 64) == [1, 1, 1])
        #expect(CoreMLMath.passes(count: 65, prefill: 64) == [64, 1])
    }

    @Test func slidingMaskMatchesTheConverter() {
        let mask = CoreMLMath.mask(sliding: true, length: 4, seq: 2, pos: 5, window: 3)
        #expect(Self.allowed(mask) == [1, 0, 0, 1, 1, 0, 1, 0, 0, 0, 1, 1])
    }

    @Test func fullMaskMatchesTheConverter() {
        let decode = CoreMLMath.mask(sliding: false, length: 6, seq: 1, pos: 3, window: 0)
        #expect(Self.allowed(decode) == [1, 1, 1, 0, 0, 0, 1])
        let first = CoreMLMath.mask(sliding: false, length: 6, seq: 3, pos: 0, window: 0)
        #expect(Self.allowed(first) == [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1])
    }

    @Test func ringRowsWrapAroundTheCache() {
        #expect(CoreMLMath.cacheRow(position: 257, length: 256) == 1)
        #expect(CoreMLMath.cachedPosition(row: 1, pos: 258, length: 256) == 257)
        #expect(CoreMLMath.cachedPosition(row: 2, pos: 258, length: 256) == 2)
        #expect(CoreMLMath.cachedPosition(row: 0, pos: 0, length: 256) == -1)
    }

    @Test func ropeMatchesTheConverter() {
        let inverse = CoreMLMath.inverseFrequencies(theta: 10000, partial: 1, headDim: 4)
        #expect(inverse == [1, Float(0.01)])
        let (cosines, sines) = CoreMLMath.rope(inverse: inverse, start: 3, count: 1)
        #expect(cosines.map(Float.init) == [-0.990234375, 0.99951171875, -0.990234375, 0.99951171875])
        #expect(sines.map(Float.init) == [0.14111328125, 0.029998779296875, 0.14111328125, 0.029998779296875])
    }

    @Test func partialRopeLeavesTheLastAnglesAtZero() {
        let inverse = CoreMLMath.inverseFrequencies(theta: 1_000_000, partial: 0.5, headDim: 8)
        #expect(inverse.count == 4)
        #expect(inverse[2] == 0 && inverse[3] == 0)
    }

    @Test func greedySamplerTakesTheBestToken() {
        var logits: [Float] = [0.5, 3, 1, 2.9]
        var sampler = CoreMLSampler(seed: 1)
        sampler.temperature = 0
        sampler.penalty = 1
        #expect(logits.withUnsafeMutableBufferPointer { sampler.sample($0, recent: []) } == 1)
    }

    @Test func penaltyCanMoveTheBestToken() {
        var logits: [Float] = [0.5, 3, 1, 2.9]
        var sampler = CoreMLSampler(seed: 1)
        sampler.temperature = 0
        #expect(logits.withUnsafeMutableBufferPointer { sampler.sample($0, recent: [1]) } == 3)
    }

    @Test func samplingStaysInTheTopTokens() {
        var sampler = CoreMLSampler(seed: 7)
        for _ in 0..<50 {
            var logits = (0..<1000).map { Float($0 % 97) }
            let token = logits.withUnsafeMutableBufferPointer { sampler.sample($0, recent: []) }
            #expect(Int(token) % 97 == 96)
        }
    }

    private static func allowed(_ mask: [Float16]) -> [Int] {
        mask.map { $0 == 0 ? 1 : 0 }
    }
}
