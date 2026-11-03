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
        let z: Double
        let born: Double
        let life: Double
        let speed: Double
        let width: Double
        let power: Double
    }

    private static let ramp: [Character] = Array(" .·:-~=+*#")
    private static let maxBlooms = 8
    private static let cameraHeight = 3.0
    private static let horizon = 0.32
    private static let spread = 2.2
    private static let ridgeGap = 0.16
    private static let lift = 0.9

    private var blooms: [Bloom] = []
    private var lastTime: Double?
    private var grid = Grid(columns: 0, rows: 0)
    private let seed = UInt32.random(in: 0...UInt32.max)

    func lines(for grid: Grid, at date: Date, mode: FieldMode) -> [String] {
        guard grid.columns > 0, grid.rows > 0 else { return [] }
        let time = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 86_400)

        if grid != self.grid {
            self.grid = grid
            blooms.removeAll()
            for _ in 0..<2 {
                spawn(at: time - Double.random(in: 0...3), mode: mode)
            }
        }
        advance(to: time, mode: mode)
        return render(at: time, mode: mode)
    }

    private func advance(to time: Double, mode: FieldMode) {
        let elapsed = min(max(time - (lastTime ?? time), 0), 1)
        lastTime = time

        let rate: Double = switch mode {
        case .think: 1.6
        case .ripple: 0.35
        case .drift: 0.55
        }
        if blooms.count < Self.maxBlooms, Double.random(in: 0..<1) < rate * elapsed {
            spawn(at: time, mode: mode)
        }
        blooms.removeAll { time - $0.born >= $0.life }
    }

    private func spawn(at time: Double, mode: FieldMode) {
        let isThink = mode == .think
        blooms.append(Bloom(
            x: .random(in: -3.5...3.5),
            z: isThink ? .random(in: 2.2...3.6) : .random(in: 2.4...8),
            born: time,
            life: isThink ? .random(in: 2.5...4.5) : .random(in: 4...8),
            speed: isThink ? .random(in: 1.1...1.8) : .random(in: 0.5...1.1),
            width: .random(in: 0.25...0.55),
            power: .random(in: 0.18...0.34)
        ))
    }

    private func render(at time: Double, mode: FieldMode) -> [String] {
        let ramp = Self.ramp
        let top = Double(ramp.count - 1)
        let columns = grid.columns
        let rowCount = grid.rows
        let rows = Double(rowCount)
        let centerX = Double(columns) / 2
        let flow = time * (mode == .think ? 0.9 : 0.35)
        let rippleZ = Self.cameraHeight / (0.5 + Self.horizon)
        let flicker = Int(time * 4)
        let near = Self.cameraHeight / (1 + Self.horizon) - Self.ridgeGap * 4
        let far = Self.cameraHeight / Self.horizon + 2
        let first = Int(((near + flow) / Self.ridgeGap).rounded(.up))
        let last = Int(((far + flow) / Self.ridgeGap).rounded(.down))

        var cells = [[Character]](repeating: [Character](repeating: " ", count: columns), count: rowCount)
        var skyline = [Double](repeating: rows, count: columns)

        if first <= last {
            for ridge in first...last {
                let depth = Double(ridge) * Self.ridgeGap - flow
                guard depth > 0.5 else { continue }
                let fog = min(1, max(0, 1.3 - depth * 0.1))
                for x in 0..<columns {
                    let worldX = (Double(x) - centerX) * 0.5 / rows * depth * Self.spread
                    let h = height(worldX, depth, time: time, flow: flow, mode: mode, rippleZ: rippleZ)
                    let y = ((Self.cameraHeight - h * Self.lift) / depth - Self.horizon) * rows
                    guard y < skyline[x] else { continue }
                    skyline[x] = y
                    let row = Int(y.rounded(.down))
                    guard row >= 0, row < rowCount else { continue }
                    let value = fog * (0.35 + 0.65 * min(1, max(0, 0.3 + h)))
                    cells[row][x] = ramp[1 + Int(min(top - 1, (value * (top - 1)).rounded(.down)))]
                }
            }
        }

        for y in 0..<rowCount {
            for x in 0..<columns where cells[y][x] == " " && hash(x &* 3 &+ flicker, y &* 7 &- flicker) > 0.998 {
                cells[y][x] = "·"
            }
        }
        return cells.map { String($0) }
    }

    private func height(_ x: Double, _ z: Double, time: Double, flow: Double, mode: FieldMode, rippleZ: Double) -> Double {
        let movingZ = z + flow
        var h = 0.32 * sin(x * 0.8 + time * 0.4) * cos(movingZ * 0.65 - time * 0.3)
        h += 0.55 * fbm(x * 0.32 + time * 0.03, movingZ * 0.32)

        for bloom in blooms {
            let age = lastTime.map { $0 - bloom.born } ?? 0
            guard age >= 0 else { continue }
            let bx = x - bloom.x
            let bz = z - bloom.z
            let distance = (bx * bx + bz * bz).squareRoot()
            let k = (distance - age * bloom.speed) / bloom.width
            guard abs(k) < 3 else { continue }
            h += exp(-k * k) * (1 - age / bloom.life) * bloom.power
        }

        if mode == .ripple {
            let distance = (x * x + (z - rippleZ) * (z - rippleZ)).squareRoot()
            h += 0.22 * cos(distance * 2.4 - time * 2.2) * exp(-distance * 0.22) * min(1, distance / 0.8)
        }
        return h
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
