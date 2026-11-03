import Foundation
import simd

final class LavaLamp {
    static let shared = LavaLamp()
    static let stride = 6

    private struct Blob {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var radius: Double
        var heat: Double
        var phase: Double
    }

    private static let poolDepth = 0.3
    private static let fingerReach = 0.32

    private var blobs: [Blob]
    private var extent = SIMD2<Double>(1, 2.1)
    private var down = SIMD2<Double>(0, 1)
    private var pull = 0.8
    private var dent = SIMD3<Double>(0, 0, 0)
    private var last: Date?

    private(set) var packed: [Float] = []

    private init() {
        let radii = [0.12, 0.09, 0.075, 0.105, 0.085, 0.07, 0.1, 0.08]
        blobs = radii.enumerated().map { index, radius in
            let fi = Double(index)
            return Blob(
                position: SIMD2(0.15 + 0.7 * (fi * 0.618).truncatingRemainder(dividingBy: 1), 0.3 + 1.5 * (fi * 0.382).truncatingRemainder(dividingBy: 1)),
                velocity: .zero,
                radius: radius,
                heat: (fi * 0.29).truncatingRemainder(dividingBy: 1),
                phase: fi * 1.7
            )
        }
        pack()
    }

    var pool: SIMD4<Float> {
        SIMD4(Float(down.x), Float(down.y), Float(bottom), Float(bottom - Self.poolDepth))
    }

    var finger: SIMD3<Float> {
        SIMD3(Float(dent.x), Float(dent.y), Float(dent.z))
    }

    private var bottom: Double {
        max(0, down.x * extent.x) + max(0, down.y * extent.y)
    }

    private var top: Double {
        min(0, down.x * extent.x) + min(0, down.y * extent.y)
    }

    func step(to date: Date, extent newExtent: SIMD2<Double>, gravity: CGPoint, touch: SIMD3<Double>, energy: Double) {
        guard date != last else { return }
        let dt = min(1.0 / 20, max(0, date.timeIntervalSince(last ?? date)))
        last = date
        extent = newExtent
        guard dt > 0 else { return }

        let raw = SIMD2(Double(gravity.x), Double(gravity.y))
        let magnitude = min(1, simd_length(raw))
        if magnitude > 0.08 {
            let follow = 1 - exp(-dt * 3)
            down = simd_normalize(down + (raw / magnitude - down) * follow)
        }
        pull += (magnitude - pull) * (1 - exp(-dt * 3))

        let follow = 1 - exp(-dt * 10)
        dent.x += (touch.x - dent.x) * follow
        dent.y += (touch.y - dent.y) * follow
        dent.z += (touch.z - dent.z) * (1 - exp(-dt * (touch.z > dent.z ? 8 : 2.5)))

        let side = SIMD2(-down.y, down.x)
        let floor = bottom, ceiling = top
        let span = max(0.001, floor - ceiling)
        let time = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
        let finger = SIMD2(touch.x, touch.y)

        for index in blobs.indices {
            var blob = blobs[index]
            let height = (floor - simd_dot(blob.position, down)) / span
            let warming = height < 0.18 ? 0.22 : -0.07 * (0.4 + height)
            blob.heat = min(1, max(0, blob.heat + warming * energy * dt))

            var force = -down * (blob.heat - 0.42) * 0.55 * (0.35 + 0.65 * pull)
            force += side * 0.03 * sin(time * 0.31 + blob.phase)
            force += down * 0.02 * sin(time * 0.23 + blob.phase * 1.3)

            if touch.z > 0.01 {
                let away = blob.position - finger
                let distance = simd_length(away)
                if distance < Self.fingerReach + blob.radius, distance > 1e-4 {
                    let fall = 1 - distance / (Self.fingerReach + blob.radius)
                    force += away / distance * fall * fall * 4 * touch.z
                }
            }

            for other in blobs.indices where other != index {
                let away = blob.position - blobs[other].position
                let distance = simd_length(away)
                let reach = (blob.radius + blobs[other].radius) * 0.8
                if distance < reach, distance > 1e-4 {
                    force += away / distance * (1 - distance / reach) * 0.25
                }
            }

            blob.velocity += force * dt
            blob.velocity *= exp(-dt * 1.4)
            let speed = simd_length(blob.velocity)
            if speed > 0.5 { blob.velocity *= 0.5 / speed }
            blob.position += blob.velocity * dt

            let margin = blob.radius * 0.5
            for axis in 0..<2 {
                if blob.position[axis] < margin {
                    blob.position[axis] = margin
                    blob.velocity[axis] = abs(blob.velocity[axis]) * 0.3
                } else if blob.position[axis] > extent[axis] - margin {
                    blob.position[axis] = extent[axis] - margin
                    blob.velocity[axis] = -abs(blob.velocity[axis]) * 0.3
                }
            }
            blobs[index] = blob
        }
        pack()
    }

    private func pack() {
        var values: [Float] = []
        values.reserveCapacity(blobs.count * Self.stride)
        for blob in blobs {
            values += [Float(blob.position.x), Float(blob.position.y), Float(blob.radius), Float(blob.velocity.x), Float(blob.velocity.y), Float(blob.heat)]
        }
        packed = values
    }
}
