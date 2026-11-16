import Foundation

nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

nonisolated struct CoreMLSampler {
    var penalty: Float = 1.1
    var penaltyWindow = 64
    var topK = 50
    var topP: Float = 0.95
    var minP: Float = 0.05
    var temperature: Float = 0.1
    var random: SplitMix64

    init(seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        random = SplitMix64(seed: seed)
    }

    static func argmax(_ logits: UnsafeBufferPointer<Float>) -> Int32 {
        var best = 0
        for i in 1..<logits.count where logits[i] > logits[best] {
            best = i
        }
        return Int32(best)
    }

    mutating func sample(_ logits: UnsafeMutableBufferPointer<Float>, recent: ArraySlice<Int32>) -> Int32 {
        if penalty != 1 {
            for token in Set(recent.suffix(penaltyWindow)) {
                let i = Int(token)
                guard i >= 0, i < logits.count else { continue }
                logits[i] = logits[i] > 0 ? logits[i] / penalty : logits[i] * penalty
            }
        }
        guard temperature > 0 else { return Self.argmax(UnsafeBufferPointer(logits)) }
        var top: [(index: Int, logit: Float)] = []
        top.reserveCapacity(topK + 1)
        for i in 0..<logits.count {
            let value = logits[i]
            if top.count < topK {
                top.append((i, value))
                if top.count == topK {
                    top.sort { $0.logit > $1.logit }
                }
            } else if value > top[topK - 1].logit {
                var j = topK - 1
                while j > 0, top[j - 1].logit < value {
                    top[j] = top[j - 1]
                    j -= 1
                }
                top[j] = (i, value)
            }
        }
        if top.count < topK {
            top.sort { $0.logit > $1.logit }
        }
        let best = top[0].logit
        let weights = top.map { exp($0.logit - best) }
        let total = weights.reduce(0, +)
        var cumulative: Float = 0
        var keep = top.count
        for (i, weight) in weights.enumerated() {
            cumulative += weight / total
            if cumulative >= topP {
                keep = i + 1
                break
            }
        }
        let floor = best + log(minP)
        let kept = top.prefix(keep).filter { $0.logit >= floor }
        let candidates = kept.isEmpty ? [top[0]] : Array(kept)
        let scaled = candidates.map { exp(($0.logit - best) / temperature) }
        let sum = scaled.reduce(0, +)
        var target = Float(Double(random.next() >> 11) / Double(1 << 53)) * sum
        for (i, weight) in scaled.enumerated() {
            target -= weight
            if target < 0 {
                return Int32(candidates[i].index)
            }
        }
        return Int32(candidates[candidates.count - 1].index)
    }
}
