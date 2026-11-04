import Foundation
import Testing
import simd
@testable import QuietGPT

struct LavaLampTests {
    private struct Driver {
        let lamp: LavaLamp
        var date = Date(timeIntervalSinceReferenceDate: 1000)

        mutating func run(seconds: Double, finger: SIMD2<Double> = .zero, pressing: Bool = false) {
            for _ in 0..<Int(seconds * 60) {
                date = date.addingTimeInterval(1.0 / 60)
                lamp.step(to: date, extent: SIMD2(1, 2.1), gravity: CGPoint(x: 0, y: 0.8), finger: finger, pressing: pressing, energy: 1)
            }
        }

        mutating func drag(from start: SIMD2<Double>, to end: SIMD2<Double>, seconds: Double) {
            let frames = Int(seconds * 60)
            for frame in 0...frames {
                date = date.addingTimeInterval(1.0 / 60)
                let point = start + (end - start) * Double(frame) / Double(frames)
                lamp.step(to: date, extent: SIMD2(1, 2.1), gravity: CGPoint(x: 0, y: 0.8), finger: point, pressing: true, energy: 1)
            }
        }
    }

    private func moved(beads: Int, seconds: Double) -> Double {
        let start = SIMD2(0.3, 0.5)
        let finger = SIMD2(0.8, 0.5)
        var driver = Driver(lamp: LavaLamp(layout: [(center: start, beads: beads)]))
        driver.run(seconds: 1.0 / 60, finger: start, pressing: false)
        let origin = driver.lamp.dropCenters[0]
        driver.run(seconds: 1.0 / 60, finger: origin, pressing: true)
        driver.run(seconds: seconds, finger: finger, pressing: true)
        return simd_length(driver.lamp.dropCenters[0] - origin) / simd_length(finger - origin)
    }

    @Test func heldDropMovesLate() {
        #expect(moved(beads: 4, seconds: 0.3) < 0.3)
    }

    @Test func heldDropArrives() {
        #expect(moved(beads: 4, seconds: 5) > 0.8)
    }

    @Test func largeDropIsSlowerThanSmallDrop() {
        #expect(moved(beads: 8, seconds: 1) < moved(beads: 2, seconds: 1))
    }

    @Test func releasedDropKeepsMoving() {
        let start = SIMD2(0.3, 0.5)
        var driver = Driver(lamp: LavaLamp(layout: [(center: start, beads: 4)]))
        driver.run(seconds: 1.0 / 60)
        driver.run(seconds: 1.0 / 60, finger: start, pressing: true)
        driver.run(seconds: 1, finger: SIMD2(0.9, 0.5), pressing: true)
        let before = driver.lamp.dropCenters[0].x
        driver.run(seconds: 0.3)
        #expect(driver.lamp.dropCenters[0].x > before + 0.01)
    }

    @Test func beadCountStaysTheSame() {
        var driver = Driver(lamp: LavaLamp())
        driver.run(seconds: 10)
        #expect(driver.lamp.beadCount == 19)
    }
}
