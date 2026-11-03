import Foundation

final class BurstEngine {
    struct Pose {
        var yaw: Double
        var pitch: Double
        var reveal: Double
    }

    private struct Vector {
        var x: Double
        var y: Double
        var z: Double

        static func - (a: Vector, b: Vector) -> Vector { Vector(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
        static func * (a: Vector, k: Double) -> Vector { Vector(x: a.x * k, y: a.y * k, z: a.z * k) }
        func dot(_ b: Vector) -> Double { x * b.x + y * b.y + z * b.z }
        var length: Double { dot(self).squareRoot() }
    }

    private static let ramp: [Character] = Array(" .:-=+*#%@")
    private static let inner = 23.0 / 49.0
    private static let radius = 0.16
    private static let extent = 1.0 + radius
    private static let maxSteps = 40
    private static let directions: [Vector] = (0..<Burst.rays).map { ray in
        let angle = -Double.pi / 2 + Double(ray) * 2 * .pi / Double(Burst.rays)
        return Vector(x: cos(angle), y: -sin(angle), z: 0)
    }
    private static let light: Vector = {
        let v = Vector(x: -0.45, y: 0.55, z: -0.7)
        return v * (1 / v.length)
    }()

    static func pose(at elapsed: Double) -> Pose {
        let spin = min(1, elapsed / 1.5)
        let settle = 1 - pow(1 - spin, 3)
        let wobble = elapsed > 1.5 ? 0.22 * sin((elapsed - 1.5) * 2.4) : 0
        return Pose(
            yaw: (1 - settle) * 2 * .pi + wobble + 0.18 * settle,
            pitch: (1 - settle) * 0.55 + 0.12 * settle,
            reveal: min(1, elapsed / 0.8)
        )
    }

    func lines(columns: Int, rows: Int, aspect: Double, pose: Pose) -> [String] {
        guard columns > 0, rows > 0 else { return [] }
        let ramp = Self.ramp
        let top = Double(ramp.count - 1)
        let scale = Self.extent * 2.1 / min(Double(columns), Double(rows) * aspect)
        let segments = segments(reveal: pose.reveal)
        let cosYaw = cos(pose.yaw), sinYaw = sin(pose.yaw)
        let cosPitch = cos(pose.pitch), sinPitch = sin(pose.pitch)

        func local(_ p: Vector) -> Vector {
            let x = p.x * cosYaw - p.z * sinYaw
            let z = p.x * sinYaw + p.z * cosYaw
            let y = p.y * cosPitch - z * sinPitch
            return Vector(x: x, y: y, z: p.y * sinPitch + z * cosPitch)
        }

        func distance(_ p: Vector) -> Double {
            var best = Double.greatestFiniteMagnitude
            for segment in segments {
                let pa = p - segment.a
                let ba = segment.b - segment.a
                let span = ba.dot(ba)
                let h = span > 0 ? min(1, max(0, pa.dot(ba) / span)) : 0
                best = min(best, (pa - ba * h).length - Self.radius)
            }
            return best
        }

        var lines: [String] = []
        lines.reserveCapacity(rows)
        for row in 0..<rows {
            var line: [Character] = []
            line.reserveCapacity(columns)
            let py = -(Double(row) - Double(rows) / 2 + 0.5) * aspect * scale
            for column in 0..<columns {
                let px = (Double(column) - Double(columns) / 2 + 0.5) * scale
                guard px * px + py * py < Self.extent * Self.extent, !segments.isEmpty else {
                    line.append(" ")
                    continue
                }
                var t = 0.0
                var hit: Vector?
                for _ in 0..<Self.maxSteps {
                    let point = local(Vector(x: px, y: py, z: -2 + t))
                    let d = distance(point)
                    if d < 0.004 {
                        hit = point
                        break
                    }
                    t += d
                    if t > 4 { break }
                }
                guard let hit else {
                    line.append(" ")
                    continue
                }
                let e = 0.01
                let normal = Vector(
                    x: distance(Vector(x: hit.x + e, y: hit.y, z: hit.z)) - distance(Vector(x: hit.x - e, y: hit.y, z: hit.z)),
                    y: distance(Vector(x: hit.x, y: hit.y + e, z: hit.z)) - distance(Vector(x: hit.x, y: hit.y - e, z: hit.z)),
                    z: distance(Vector(x: hit.x, y: hit.y, z: hit.z + e)) - distance(Vector(x: hit.x, y: hit.y, z: hit.z - e))
                )
                let worldLight = local(Self.light)
                let diffuse = max(0, normal.dot(worldLight) / max(normal.length, 1e-6))
                let value = 0.1 + 0.9 * diffuse
                let index = 1 + Int(min(top - 1, (value * (top - 1)).rounded(.down)))
                line.append(ramp[index])
            }
            lines.append(String(line))
        }
        return lines
    }

    private func segments(reveal: Double) -> [(a: Vector, b: Vector)] {
        Self.directions.enumerated().compactMap { ray, direction in
            let grow = min(1, max(0, reveal * 1.7 - Double(ray) * 0.09))
            guard grow > 0 else { return nil }
            return (direction * Self.inner, direction * (Self.inner + (1 - Self.inner) * grow))
        }
    }
}
