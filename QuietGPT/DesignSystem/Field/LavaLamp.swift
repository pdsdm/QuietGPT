import Foundation
import simd

final class LavaLamp {
    static let shared = LavaLamp()
    static let stride = 6

    private struct Blob {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var radius: Double
        var tone: Double
        var phase: Double
        var pace: Double
    }

    private static let grabReach = 1.6

    private var blobs: [Blob]
    private var extent = SIMD2<Double>(1, 2.1)
    private var down = SIMD2<Double>(0, 1)
    private var pull = 0.8
    private var grabbed: Int?
    private var grip = SIMD2<Double>(0, 0)
    private var wasPressing = false
    private var spawns = 0
    private var last: Date?

    private(set) var packed: [Float] = []

    private init() {
        let radii = [0.12, 0.09, 0.075, 0.105, 0.085, 0.07, 0.1, 0.08]
        blobs = radii.enumerated().map { index, radius in
            let fi = Double(index)
            return Blob(
                position: SIMD2(0.15 + 0.7 * (fi * 0.618).truncatingRemainder(dividingBy: 1), 0.1 + 2 * (fi * 0.382).truncatingRemainder(dividingBy: 1)),
                velocity: .zero,
                radius: radius,
                tone: (fi * 0.29).truncatingRemainder(dividingBy: 1),
                phase: fi * 1.7,
                pace: 0.6 + 0.8 * (fi * 0.447).truncatingRemainder(dividingBy: 1)
            )
        }
        pack()
    }

    var direction: SIMD2<Float> {
        SIMD2(Float(down.x), Float(down.y))
    }

    func step(to date: Date, extent newExtent: SIMD2<Double>, gravity: CGPoint, finger: SIMD2<Double>, pressing: Bool, energy: Double) {
        guard date != last else { return }
        let dt = min(1.0 / 20, max(0, date.timeIntervalSince(last ?? date)))
        last = date
        extent = newExtent
        guard dt > 0 else { return }

        let raw = SIMD2(Double(gravity.x), Double(gravity.y))
        let magnitude = min(1, simd_length(raw))
        if magnitude > 0.08 {
            down = simd_normalize(down + (raw / magnitude - down) * (1 - exp(-dt * 3)))
        }
        pull += (magnitude - pull) * (1 - exp(-dt * 3))

        if pressing, !wasPressing {
            grabbed = blobs.indices
                .map { (index: $0, distance: simd_length(blobs[$0].position - finger) / blobs[$0].radius) }
                .filter { $0.distance < Self.grabReach }
                .min { $0.distance < $1.distance }?
                .index
            if let grabbed { grip = blobs[grabbed].position - finger }
        }
        if !pressing { grabbed = nil }
        wasPressing = pressing

        let side = SIMD2(-down.y, down.x)
        let time = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)

        for index in blobs.indices {
            var blob = blobs[index]

            var force = down * 0.05 * blob.pace * energy * (0.3 + 0.7 * pull)
            force += side * 0.025 * sin(time * 0.31 + blob.phase)
            force -= down * 0.03 * sin(time * 0.43 * blob.pace + blob.phase * 1.3)

            for other in blobs.indices where other != index {
                let away = blob.position - blobs[other].position
                let distance = simd_length(away)
                let reach = (blob.radius + blobs[other].radius) * 0.8
                if distance < reach, distance > 1e-4 {
                    force += away / distance * (1 - distance / reach) * 0.25
                }
            }

            if index == grabbed {
                grip *= exp(-dt * 3)
                let target = finger + grip
                blob.velocity = (target - blob.position) * min(1, dt * 18) / dt
                blob.position += blob.velocity * dt
                blobs[index] = blob
                continue
            }

            blob.velocity += force * dt
            blob.velocity *= exp(-dt * 1.4)
            let speed = simd_length(blob.velocity)
            if speed > 1.2 { blob.velocity *= 1.2 / speed }
            blob.position += blob.velocity * dt

            let margin = blob.radius * 2
            let outside = blob.position.x < -margin || blob.position.y < -margin
                || blob.position.x > extent.x + margin || blob.position.y > extent.y + margin
            if outside { respawn(&blob) }
            blobs[index] = blob
        }
        pack()
    }

    private func respawn(_ blob: inout Blob) {
        spawns += 1
        let seed = Double(spawns)
        let point = SIMD2(
            extent.x * (0.1 + 0.8 * (seed * 0.618).truncatingRemainder(dividingBy: 1)),
            extent.y * (0.1 + 0.8 * (seed * 0.382).truncatingRemainder(dividingBy: 1))
        )
        var back = Double.greatestFiniteMagnitude
        for axis in 0..<2 where abs(down[axis]) > 1e-4 {
            let distance = down[axis] > 0 ? point[axis] / down[axis] : (point[axis] - extent[axis]) / down[axis]
            back = min(back, distance)
        }
        blob.position = point - down * (back + blob.radius * 1.9)
        blob.velocity = down * 0.04
    }

    private func pack() {
        var values: [Float] = []
        values.reserveCapacity(blobs.count * Self.stride)
        for blob in blobs {
            values += [Float(blob.position.x), Float(blob.position.y), Float(blob.radius), Float(blob.velocity.x), Float(blob.velocity.y), Float(blob.tone)]
        }
        packed = values
    }
}
