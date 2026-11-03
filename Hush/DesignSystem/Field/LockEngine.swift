import Foundation

final class LockEngine {
    struct Pose {
        var yaw: Double
        var pitch: Double
        var swing: Double
        var lift: Double
    }

    private struct Vector {
        var x: Double
        var y: Double
        var z: Double

        static func - (a: Vector, b: Vector) -> Vector { Vector(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
        static func + (a: Vector, b: Vector) -> Vector { Vector(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
        static func * (a: Vector, k: Double) -> Vector { Vector(x: a.x * k, y: a.y * k, z: a.z * k) }
        func dot(_ b: Vector) -> Double { x * b.x + y * b.y + z * b.z }
        var length: Double { dot(self).squareRoot() }
    }

    private struct Group {
        let occupied: [Bool]
        let low: Vector
        let high: Vector
    }

    private static let unit = 0.4
    private static let half = unit * 0.45
    private static let rounding = 0.03
    private static let pivotX = -2 * unit
    private static let pivotY = 0.5 * unit
    private static let openLift = 0.24
    private static let openSwing = 0.24
    private static let extent = 1.72
    private static let maxSteps = 48
    static let pace = 1.6
    static let settled = 1.7 * pace
    static let closed = 1.25 * pace
    private static let ramp = AsciiGlyphs.ramp
    private static let reachCap = 1.5 * unit - half
    private static let light: Vector = {
        let v = Vector(x: -0.45, y: 0.6, z: -0.66)
        return v * (1 / v.length)
    }()

    private static let body = group(LockMark.cells.filter { $0.row >= 2 })
    private static let shackle = group(LockMark.cells.filter { $0.row < 2 })

    private static func group(_ cells: [(column: Int, row: Int)]) -> Group {
        let centers = cells.map { Vector(x: Double($0.column - 2) * unit, y: Double(2 - $0.row) * unit, z: 0) }
        let xs = centers.map(\.x), ys = centers.map(\.y)
        var occupied = Array(repeating: false, count: LockMark.size * LockMark.size)
        for cell in cells { occupied[cell.row * LockMark.size + cell.column] = true }
        return Group(
            occupied: occupied,
            low: Vector(x: xs.min()! - half, y: ys.min()! - half, z: -half),
            high: Vector(x: xs.max()! + half, y: ys.max()! + half, z: half)
        )
    }

    static func pose(at time: Double) -> Pose {
        let elapsed = time / pace
        func ease(_ t: Double) -> Double { let c = min(1, max(0, t)); return c * c * (3 - 2 * c) }
        let turn = ease(elapsed / 1.7)
        let swing = openSwing * (1 - ease((elapsed - 0.35) / 0.55))
        var lift = openLift
        if elapsed > 0.95 {
            let fall = min(1, (elapsed - 0.95) / 0.22)
            lift = openLift * (1 - fall * fall)
        }
        if elapsed > 1.17 {
            let bounce = elapsed - 1.17
            lift = 0.05 * max(0, sin(bounce * 14)) * exp(-bounce * 9)
        }
        let wobble = elapsed > 1.7 ? 0.1 * sin((elapsed - 1.7) * 2.2) : 0
        return Pose(
            yaw: 0.35 * (1 - turn) + 0.18 * turn + wobble,
            pitch: -0.22 * (1 - turn) - 0.14 * turn,
            swing: swing,
            lift: lift
        )
    }

    func lines(columns: Int, rows: Int, aspect: Double, pose: Pose) -> [String] {
        guard columns > 0, rows > 0 else { return [] }
        let ramp = Self.ramp
        let top = Double(ramp.count - 1)
        let scale = Self.extent * 2 / min(Double(columns), Double(rows) * aspect)
        let cosYaw = cos(pose.yaw), sinYaw = sin(pose.yaw)
        let cosPitch = cos(pose.pitch), sinPitch = sin(pose.pitch)
        let cosSwing = cos(pose.swing), sinSwing = sin(pose.swing)
        let centerY = -0.1 + pose.swing * 1.2

        func local(_ p: Vector) -> Vector {
            let y = p.y * cosPitch + p.z * sinPitch
            let z = -p.y * sinPitch + p.z * cosPitch
            return Vector(x: p.x * cosYaw - z * sinYaw, y: y, z: p.x * sinYaw + z * cosYaw)
        }

        func shackleSpace(_ p: Vector) -> Vector {
            let x = p.x - Self.pivotX
            let y = p.y - pose.lift - Self.pivotY
            return Vector(x: x * cosSwing + y * sinSwing + Self.pivotX, y: -x * sinSwing + y * cosSwing + Self.pivotY, z: p.z)
        }

        func box(_ p: Vector, _ cx: Double, _ cy: Double) -> Double {
            let inner = Self.half - Self.rounding
            let qx = abs(p.x - cx) - inner
            let qy = abs(p.y - cy) - inner
            let qz = abs(p.z) - inner
            let outside = Vector(x: max(qx, 0), y: max(qy, 0), z: max(qz, 0)).length
            return outside + min(max(qx, max(qy, qz)), 0) - Self.rounding
        }

        func bound(_ p: Vector, _ group: Group) -> Double {
            let dx = max(group.low.x - p.x, 0, p.x - group.high.x)
            let dy = max(group.low.y - p.y, 0, p.y - group.high.y)
            let dz = max(group.low.z - p.z, 0, p.z - group.high.z)
            return (dx * dx + dy * dy + dz * dz).squareRoot()
        }

        func distance(_ g: Vector, _ group: Group) -> Double {
            let far = bound(g, group)
            if far > 0.25 { return far }
            let size = LockMark.size
            let column = Int((g.x / Self.unit + 2).rounded())
            let row = Int((2 - g.y / Self.unit).rounded())
            var best = Self.reachCap
            for r in stride(from: max(0, row - 1), through: min(size - 1, row + 1), by: 1) {
                for c in stride(from: max(0, column - 1), through: min(size - 1, column + 1), by: 1) where group.occupied[r * size + c] {
                    best = min(best, box(g, Double(c - 2) * Self.unit, Double(2 - r) * Self.unit))
                }
            }
            return best
        }

        func scene(_ p: Vector) -> Double {
            min(distance(p, Self.body), distance(shackleSpace(p), Self.shackle))
        }

        let viewLight = Self.light
        var lines: [String] = []
        lines.reserveCapacity(rows)
        for row in 0..<rows {
            var line: [Character] = []
            line.reserveCapacity(columns)
            let py = -(Double(row) - Double(rows) / 2 + 0.5) * aspect * scale + centerY
            for column in 0..<columns {
                let px = (Double(column) - Double(columns) / 2 + 0.5) * scale
                let dy = py - centerY
                guard px * px + dy * dy < Self.extent * Self.extent else {
                    line.append(" ")
                    continue
                }
                var t = 0.0
                var hit: Vector?
                for _ in 0..<Self.maxSteps {
                    let point = local(Vector(x: px, y: py, z: -3 + t))
                    let d = scene(point)
                    if d < 0.003 {
                        hit = point
                        break
                    }
                    t += d
                    if t > 6 { break }
                }
                guard let hit else {
                    line.append(" ")
                    continue
                }
                let e = 0.008
                let normal = Vector(
                    x: scene(Vector(x: hit.x + e, y: hit.y, z: hit.z)) - scene(Vector(x: hit.x - e, y: hit.y, z: hit.z)),
                    y: scene(Vector(x: hit.x, y: hit.y + e, z: hit.z)) - scene(Vector(x: hit.x, y: hit.y - e, z: hit.z)),
                    z: scene(Vector(x: hit.x, y: hit.y, z: hit.z + e)) - scene(Vector(x: hit.x, y: hit.y, z: hit.z - e))
                )
                let unitNormal = normal * (1 / max(normal.length, 1e-6))
                let lightDirection = local(viewLight)
                let diffuse = max(0, unitNormal.dot(lightDirection))
                let toEye = local(Vector(x: 0, y: 0, z: -1))
                let halfway = lightDirection + toEye
                let shine = pow(max(0, unitNormal.dot(halfway * (1 / max(halfway.length, 1e-6)))), 24)
                let value = min(1, 0.1 + 0.72 * diffuse + 0.35 * shine)
                line.append(ramp[1 + Int(min(top - 1, (value * (top - 1)).rounded(.down)))])
            }
            lines.append(String(line))
        }
        return lines
    }
}
