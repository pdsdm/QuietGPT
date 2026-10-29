import Foundation

enum FieldMode: Equatable {
    case drift
    case ripple
    case think
}

final class FieldEngine {
    struct Grid: Equatable {
        let columns: Int
        let rows: Int
    }

    private struct Bloom {
        let x: Double
        let y: Double
        let born: Double
        let life: Double
        let speed: Double
        let width: Double
        let power: Double
    }

    private static let ramp: [Character] = Array("   ..·:-=+*#")
    private static let ticksPerSecond = 12.5
    private static let maxBlooms = 10

    private var blooms: [Bloom] = []
    private var lastTick: Double?
    private var grid = Grid(columns: 0, rows: 0)
    private let seed = UInt32.random(in: 0...UInt32.max)

    func lines(for grid: Grid, at date: Date, mode: FieldMode) -> [String] {
        guard grid.columns > 0, grid.rows > 0 else { return [] }
        let tick = date.timeIntervalSinceReferenceDate * Self.ticksPerSecond

        if grid != self.grid {
            self.grid = grid
            blooms.removeAll()
            for _ in 0..<3 {
                spawn(at: tick - Double.random(in: 0...30), mode: mode)
            }
        }
        advance(to: tick, mode: mode)
        return render(at: tick, mode: mode)
    }

    private func advance(to tick: Double, mode: FieldMode) {
        let elapsed = min(max(tick - (lastTick ?? tick), 0), 10)
        lastTick = tick

        let rate: Double = switch mode {
        case .think: 0.28
        case .ripple: 0.05
        case .drift: 0.07
        }
        let chance = 1 - pow(1 - rate, elapsed)
        if blooms.count < Self.maxBlooms, Double.random(in: 0..<1) < chance {
            spawn(at: tick, mode: mode)
        }
        blooms.removeAll { tick - $0.born >= $0.life }
    }

    private func spawn(at tick: Double, mode: FieldMode) {
        let columns = Double(grid.columns)
        let rows = Double(grid.rows)
        let isThink = mode == .think
        let isBig = Double.random(in: 0..<1) < 0.25

        blooms.append(Bloom(
            x: .random(in: 0...columns),
            y: isThink ? rows * .random(in: 0.7...1.0) : .random(in: 0...rows),
            born: tick,
            life: isThink ? .random(in: 25...55) : .random(in: 40...100),
            speed: (isThink ? 0.5 : 0.22) + .random(in: 0...(isBig ? 0.5 : 0.3)),
            width: 1.2 + .random(in: 0...(isBig ? 2.4 : 1.2)),
            power: .random(in: 0.55...1.0)
        ))
    }

    private func render(at tick: Double, mode: FieldMode) -> [String] {
        let ramp = Self.ramp
        let top = Double(ramp.count - 1)
        let columns = grid.columns
        let rows = grid.rows
        let centerX = Double(columns) / 2
        let centerY = Double(rows) / 2
        let reach = max(Double(rows), Double(columns) * 0.5)
        let quiet = max(2, reach * 0.1)
        let flow = mode == .think ? 0.05 : 0.02
        let flicker = Int(tick / 3)

        var lines: [String] = []
        lines.reserveCapacity(rows)

        for y in 0..<rows {
            var line: [Character] = []
            line.reserveCapacity(columns)
            let py = Double(y) * 0.16

            for x in 0..<columns {
                let px = Double(x) * 0.08
                let warp = fbm(px + tick * 0.008, py - tick * 0.006)
                let base = fbm(px + warp * 1.8 + tick * flow, py + warp * 1.2 - tick * flow * 0.7)
                var value = pow(max(0, base - 0.25) / 0.75, 2.2) * 0.75

                for bloom in blooms {
                    let age = tick - bloom.born
                    guard age >= 0 else { continue }
                    let dx = (Double(x) - bloom.x) * 0.5
                    let dy = Double(y) - bloom.y
                    let distance = (dx * dx + dy * dy).squareRoot()
                    let radius = age * bloom.speed
                    let k = (distance - radius) / bloom.width
                    let fade = 1 - age / bloom.life
                    var ring = exp(-k * k) * fade * bloom.power
                    if distance < radius {
                        ring += 0.12 * fade * exp(-(radius - distance) * 0.25)
                    }
                    value = max(value, ring)
                }

                if mode == .ripple {
                    let dx = (Double(x) - centerX) * 0.5
                    let dy = Double(y) - centerY
                    let distance = (dx * dx + dy * dy).squareRoot()
                    let ring = 0.5 + 0.5 * cos(distance * 0.6 + tick * 0.2)
                    let inner = min(1, max(0, (distance - quiet) / 6))
                    let outer = max(0, 1 - distance / (reach * 0.75))
                    value = max(value * inner, ring * inner * outer * 0.7)
                }

                if value < 0.2, hash(x &* 3 &+ flicker, y &* 7 &- flicker) > 0.9965 {
                    value = 0.85
                }

                let index = Int(min(top, max(0, (value * top).rounded(.down))))
                line.append(ramp[index])
            }
            lines.append(String(line))
        }
        return lines
    }

    private func hash(_ x: Int, _ y: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263) ^ seed
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Double(h) / Double(UInt32.max)
    }

    private func noise(_ x: Double, _ y: Double) -> Double {
        let ix = Int(x.rounded(.down))
        let iy = Int(y.rounded(.down))
        let fx = x - Double(ix)
        let fy = y - Double(iy)
        let ux = fx * fx * (3 - 2 * fx)
        let uy = fy * fy * (3 - 2 * fy)
        let a = hash(ix, iy)
        let b = hash(ix + 1, iy)
        let c = hash(ix, iy + 1)
        let d = hash(ix + 1, iy + 1)
        return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy
    }

    private func fbm(_ x: Double, _ y: Double) -> Double {
        noise(x, y) * 0.65 + noise(x * 2.1 + 5.2, y * 2.1 + 1.3) * 0.35
    }
}
