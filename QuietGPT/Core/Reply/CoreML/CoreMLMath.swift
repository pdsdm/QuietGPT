import Foundation

nonisolated enum CoreMLMath {
    static let maskedValue = Float16(-65504)

    static func passes(count: Int, prefill: Int) -> [Int] {
        guard prefill > 1 else { return Array(repeating: 1, count: count) }
        return Array(repeating: prefill, count: count / prefill) + Array(repeating: 1, count: count % prefill)
    }

    static func inverseFrequencies(theta: Double, partial: Double, headDim: Int) -> [Float] {
        let angles = Int(partial * Double(headDim)) / 2
        return (0..<headDim / 2).map { i in
            i < angles ? Float(1.0 / pow(theta, Double(2 * i) / Double(headDim))) : 0
        }
    }

    static func rope(inverse: [Float], start: Int, count: Int) -> (cos: [Float16], sin: [Float16]) {
        let half = inverse.count
        let width = half * 2
        var cosines = [Float16](repeating: 0, count: count * width)
        var sines = [Float16](repeating: 0, count: count * width)
        for t in 0..<count {
            let position = Float(start + t)
            for j in 0..<half {
                let angle = position * inverse[j]
                let c = Float16(cos(angle))
                let s = Float16(sin(angle))
                cosines[t * width + j] = c
                cosines[t * width + half + j] = c
                sines[t * width + j] = s
                sines[t * width + half + j] = s
            }
        }
        return (cosines, sines)
    }

    static func cachedPosition(row: Int, pos: Int, length: Int) -> Int {
        guard pos > 0 else { return -1 }
        let offset = (pos - 1 - row) % length
        return pos - 1 - (offset < 0 ? offset + length : offset)
    }

    static func cacheRow(position: Int, length: Int) -> Int {
        position % length
    }

    static func mask(sliding: Bool, length: Int, seq: Int, pos: Int, window: Int) -> [Float16] {
        let width = length + seq
        var values = [Float16](repeating: maskedValue, count: seq * width)
        let past = (0..<length).map { cachedPosition(row: $0, pos: pos, length: length) }
        for q in 0..<seq {
            let query = pos + q
            let floor = sliding ? query - (window - 1) : Int.min
            for r in 0..<length {
                let p = past[r]
                if p >= 0, p <= query, p >= floor {
                    values[q * width + r] = 0
                }
            }
            for n in 0..<seq {
                let p = pos + n
                if p <= query, p >= floor {
                    values[q * width + length + n] = 0
                }
            }
        }
        return values
    }
}
