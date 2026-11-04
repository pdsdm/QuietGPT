import Foundation
import simd

final class LavaLamp {
    static let shared = LavaLamp()
    static let stride = 6

    private enum Tuning {
        static let grabReach = 1.6
        static let spacing = 0.75
        static let cohesion = 5.0
        static let viscosity = 3.0
        static let separation = 2.0
        static let drag = 1.0
        static let pull = 6.0
        static let pullReach = 0.5
        static let lead = 0.15
        static let holdDamping = 0.85
        static let maxSpeed = 1.2
        static let parallax = 0.02
        static let mergeDistance = 0.85
        static let mergeDelay = 0.2
        static let mergeLimit = 12
        static let pushReach = 1.4
        static let pushForce = 1.0
    }

    private struct DropPair: Hashable {
        let low: Int
        let high: Int

        init(_ first: Int, _ second: Int) {
            low = min(first, second)
            high = max(first, second)
        }
    }

    private struct Bead {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double> = .zero
        var radius: Double
        var depth = 0.5
        var phase: Double
        var rest: SIMD2<Double> = .zero
        var drop: Int
    }

    private struct Drop {
        var pace: Double
        var phase: Double
        var noMergeUntil = 0.0
    }

    private enum Touch {
        case idle
        case holding(drop: Int, bead: Int, grip: SIMD2<Double>)
    }

    private var beads: [Bead] = []
    private var drops: [Int: Drop] = [:]
    private var extent = SIMD2<Double>(1, 2.1)
    private var down = SIMD2<Double>(0, 1)
    private var pull = 0.8
    private var touch = Touch.idle
    private var wasPressing = false
    private var spawns = 0
    private var clock = 0.0
    private var nextDrop = 0
    private var contacts: [DropPair: Double] = [:]
    private var last: Date?

    private(set) var packed: [Float] = []

    convenience init() {
        let sizes = [4, 2, 2, 3, 2, 1, 3, 2]
        self.init(layout: sizes.enumerated().map { index, size in
            let fi = Double(index)
            return (
                center: SIMD2(0.15 + 0.7 * (fi * 0.618).truncatingRemainder(dividingBy: 1), 0.1 + 2 * (fi * 0.382).truncatingRemainder(dividingBy: 1)),
                beads: size
            )
        })
    }

    init(layout: [(center: SIMD2<Double>, beads: Int)]) {
        for (index, item) in layout.enumerated() {
            let fi = Double(index)
            let id = nextDrop
            nextDrop += 1
            drops[id] = Drop(pace: 0.6 + 0.8 * (fi * 0.447).truncatingRemainder(dividingBy: 1), phase: fi * 1.7)
            for bead in 0..<item.beads {
                let seed = Double(beads.count)
                let angle = seed * 2.399
                let reach = 0.055 * sqrt(Double(bead)) * (0.8 + 0.5 * (seed * 0.731).truncatingRemainder(dividingBy: 1))
                beads.append(Bead(
                    position: item.center + SIMD2(cos(angle), sin(angle)) * reach,
                    radius: 0.05 + 0.02 * (seed * 0.618).truncatingRemainder(dividingBy: 1),
                    phase: seed * 1.3,
                    drop: id
                ))
            }
            settle(drop: id)
        }
        pack()
    }

    var direction: SIMD2<Float> {
        SIMD2(Float(down.x), Float(down.y))
    }

    var beadCount: Int {
        beads.count
    }

    var dropSizes: [Int] {
        groups.keys.sorted().compactMap { groups[$0]?.count }
    }

    var dropCenters: [SIMD2<Double>] {
        groups.keys.sorted().map { center(of: $0) }
    }

    func step(to date: Date, extent newExtent: SIMD2<Double>, gravity: CGPoint, finger: SIMD2<Double>, pressing: Bool, energy: Double) {
        guard date != last else { return }
        let dt = min(1.0 / 20, max(0, date.timeIntervalSince(last ?? date)))
        last = date
        extent = newExtent
        guard dt > 0 else { return }
        clock += dt

        let raw = SIMD2(Double(gravity.x), Double(gravity.y))
        let magnitude = min(1, simd_length(raw))
        if magnitude > 0.08 {
            down = simd_normalize(down + (raw / magnitude - down) * (1 - exp(-dt * 3)))
        }
        pull += (magnitude - pull) * (1 - exp(-dt * 3))

        updateTouch(finger: finger, pressing: pressing, dt: dt)
        mergeTouchingDrops(dt: dt)
        moveBeads(finger: finger, energy: energy, dt: dt)
        respawnLostDrops()
        pack()
    }

    private var groups: [Int: [Int]] {
        Dictionary(grouping: beads.indices) { beads[$0].drop }
    }

    private func center(of drop: Int) -> SIMD2<Double> {
        center(of: groups[drop] ?? [])
    }

    private func center(of members: [Int]) -> SIMD2<Double> {
        guard !members.isEmpty else { return .zero }
        return members.reduce(SIMD2<Double>.zero) { $0 + beads[$1].position } / Double(members.count)
    }

    private func updateTouch(finger: SIMD2<Double>, pressing: Bool, dt: Double) {
        if pressing, !wasPressing {
            let hit = beads.indices
                .map { (index: $0, distance: simd_length(beads[$0].position - finger) / beads[$0].radius) }
                .filter { $0.distance < Tuning.grabReach }
                .min { $0.distance < $1.distance }?
                .index
            if let hit {
                touch = .holding(drop: beads[hit].drop, bead: hit, grip: beads[hit].position - finger)
            }
        }
        if !pressing { touch = .idle }
        wasPressing = pressing
        if case .holding(let drop, let bead, let grip) = touch {
            touch = .holding(drop: drop, bead: bead, grip: grip * exp(-dt * 3))
        }
    }

    private func moveBeads(finger: SIMD2<Double>, energy: Double, dt: Double) {
        let side = SIMD2(-down.y, down.x)
        var acceleration = [SIMD2<Double>](repeating: .zero, count: beads.count)

        for (id, members) in groups {
            let count = Double(members.count)
            let middle = center(of: members)
            let flow = members.reduce(SIMD2<Double>.zero) { $0 + beads[$1].velocity } / count
            var inner = [SIMD2<Double>](repeating: .zero, count: members.count)

            for (slot, index) in members.enumerated() {
                let bead = beads[index]
                let breathe = 1 + 0.25 * sin(clock * 0.4 + bead.phase)
                let turn = 0.25 * sin(clock * 0.17 + bead.phase)
                let rest = bead.rest * breathe
                let target = middle + SIMD2(rest.x * cos(turn) - rest.y * sin(turn), rest.x * sin(turn) + rest.y * cos(turn))
                inner[slot] += (target - bead.position) * Tuning.cohesion

                for other in members where other != index {
                    let away = bead.position - beads[other].position
                    let distance = simd_length(away)
                    let reach = (bead.radius + beads[other].radius) * Tuning.spacing
                    if distance < reach, distance > 1e-4 {
                        inner[slot] += away / distance * (1 - distance / reach) * Tuning.separation
                    }
                }
                beads[index].velocity += (flow - bead.velocity) * (1 - exp(-dt * Tuning.viscosity))
                beads[index].depth = 0.5 + 0.5 * sin(clock * 0.35 + bead.phase)
            }

            let balance = inner.reduce(SIMD2<Double>.zero, +) / count
            for (slot, index) in members.enumerated() {
                acceleration[index] = inner[slot] - balance
            }

            var damping = Tuning.drag
            if case .holding(id, let held, let grip) = touch {
                let gap = finger + grip - beads[held].position
                let distance = simd_length(gap)
                let force = (distance > Tuning.pullReach ? gap / distance * Tuning.pullReach : gap) * Tuning.pull
                let share = (1 - Tuning.lead) / count
                for index in members {
                    acceleration[index] += force * (index == held ? Tuning.lead + share : share)
                }
                damping = 2 * Tuning.holdDamping * sqrt(Tuning.pull / count)
            } else if let drop = drops[id] {
                var drift = down * 0.05 * drop.pace * energy * (0.3 + 0.7 * pull)
                drift += side * 0.025 * sin(clock * 0.31 + drop.phase)
                drift -= down * 0.03 * sin(clock * 0.43 * drop.pace + drop.phase * 1.3)
                for index in members { acceleration[index] += drift }
            }

            for index in members {
                var velocity = (beads[index].velocity + acceleration[index] * dt) * exp(-dt * damping)
                let speed = simd_length(velocity)
                if speed > Tuning.maxSpeed { velocity *= Tuning.maxSpeed / speed }
                beads[index].velocity = velocity
            }
        }

        for index in beads.indices {
            beads[index].position += beads[index].velocity * dt
        }
    }

    private func mergeTouchingDrops(dt: Double) {
        let sizes = groups.mapValues(\.count)
        var touching = Set<DropPair>()

        for first in beads.indices {
            for second in beads.indices where second > first && beads[first].drop != beads[second].drop {
                let away = beads[first].position - beads[second].position
                let distance = simd_length(away)
                let reach = beads[first].radius + beads[second].radius
                guard distance > 1e-4 else { continue }
                let pair = DropPair(beads[first].drop, beads[second].drop)
                if canMerge(pair, sizes: sizes) {
                    if distance < reach * Tuning.mergeDistance { touching.insert(pair) }
                } else if distance < reach * Tuning.pushReach {
                    let push = away / distance * (1 - distance / (reach * Tuning.pushReach)) * Tuning.pushForce * dt
                    beads[first].velocity += push
                    beads[second].velocity -= push
                }
            }
        }

        contacts = contacts.filter { touching.contains($0.key) }
        for pair in touching { contacts[pair, default: 0] += dt }
        guard let ready = contacts.filter({ $0.value >= Tuning.mergeDelay }).keys.min(by: { ($0.low, $0.high) < ($1.low, $1.high) }) else { return }
        merge(ready)
    }

    private func canMerge(_ pair: DropPair, sizes: [Int: Int]) -> Bool {
        guard let low = drops[pair.low], let high = drops[pair.high] else { return false }
        return (sizes[pair.low] ?? 0) + (sizes[pair.high] ?? 0) <= Tuning.mergeLimit
            && clock >= low.noMergeUntil
            && clock >= high.noMergeUntil
    }

    private func merge(_ pair: DropPair) {
        var kept = pair.low
        var gone = pair.high
        if case .holding(pair.high, _, _) = touch { swap(&kept, &gone) }
        for index in beads.indices where beads[index].drop == gone {
            beads[index].drop = kept
        }
        drops[gone] = nil
        contacts = contacts.filter { $0.key.low != gone && $0.key.high != gone }
        settle(drop: kept)
    }

    private func settle(drop: Int) {
        let members = groups[drop] ?? []
        let middle = center(of: members)
        let limit = 0.055 * sqrt(Double(members.count)) * 1.2
        let farthest = members.map { simd_length(beads[$0].position - middle) }.max() ?? 0
        let scale = farthest > limit ? limit / farthest : 1
        for index in members {
            beads[index].rest = (beads[index].position - middle) * scale
        }
    }

    private func respawnLostDrops() {
        var heldDrop: Int?
        if case .holding(let drop, _, _) = touch { heldDrop = drop }
        for (id, members) in groups where id != heldDrop {
            let lost = members.allSatisfy { index in
                let margin = beads[index].radius * 2
                let point = beads[index].position
                return point.x < -margin || point.y < -margin || point.x > extent.x + margin || point.y > extent.y + margin
            }
            if lost { respawn(members) }
        }
    }

    private func respawn(_ members: [Int]) {
        spawns += 1
        let seed = Double(spawns)
        let middle = center(of: members)
        let size = members.map { simd_length(beads[$0].position - middle) + beads[$0].radius }.max() ?? 0
        let point = SIMD2(
            extent.x * (0.1 + 0.8 * (seed * 0.618).truncatingRemainder(dividingBy: 1)),
            extent.y * (0.1 + 0.8 * (seed * 0.382).truncatingRemainder(dividingBy: 1))
        )
        var back = Double.greatestFiniteMagnitude
        for axis in 0..<2 where abs(down[axis]) > 1e-4 {
            let distance = down[axis] > 0 ? point[axis] / down[axis] : (point[axis] - extent[axis]) / down[axis]
            back = min(back, distance)
        }
        let shift = point - down * (back + size * 1.9) - middle
        for index in members {
            beads[index].position += shift
            beads[index].velocity = down * 0.04
        }
    }

    private func pack() {
        let tilt = (down - SIMD2(0, 1)) * Tuning.parallax
        var values: [Float] = []
        values.reserveCapacity(beads.count * Self.stride)
        for bead in beads {
            let point = bead.position + tilt * bead.depth
            values += [Float(point.x), Float(point.y), Float(bead.radius), Float(bead.velocity.x), Float(bead.velocity.y), Float(bead.depth)]
        }
        packed = values
    }
}
