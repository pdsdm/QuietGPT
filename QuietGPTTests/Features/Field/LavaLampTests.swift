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

    @Test func touchingDropsBecomeOne() {
        var driver = Driver(lamp: LavaLamp(layout: [
            (center: SIMD2(0.45, 0.5), beads: 2),
            (center: SIMD2(0.53, 0.5), beads: 3)
        ]))
        driver.run(seconds: 0.5)
        #expect(driver.lamp.dropSizes == [5])
        #expect(driver.lamp.beadCount == 5)
    }

    @Test func mergeStopsAtTheSizeLimit() {
        var driver = Driver(lamp: LavaLamp(layout: [
            (center: SIMD2(0.42, 0.5), beads: 8),
            (center: SIMD2(0.58, 0.5), beads: 8)
        ]))
        driver.run(seconds: 2)
        #expect(driver.lamp.dropSizes == [8, 8])
    }

    private func swiped(beads: Int) -> Driver {
        var driver = Driver(lamp: LavaLamp(layout: [(center: SIMD2(0.5, 0.5), beads: beads)]))
        driver.run(seconds: 1.0 / 60)
        driver.drag(from: SIMD2(0.05, 0.5), to: SIMD2(0.95, 0.5), seconds: 1)
        return driver
    }

    @Test func dragFromEmptySpaceDividesLargeDrop() {
        let driver = swiped(beads: 4)
        #expect(driver.lamp.dropSizes.count == 2)
        #expect(driver.lamp.beadCount == 4)
    }

    @Test func dragFromEmptySpaceDoesNotDivideSmallDrop() {
        let driver = swiped(beads: 2)
        #expect(driver.lamp.dropSizes == [2])
    }

    @Test func dragFromDropDoesNotDivideIt() {
        var driver = Driver(lamp: LavaLamp(layout: [(center: SIMD2(0.5, 0.5), beads: 4)]))
        driver.run(seconds: 1.0 / 60)
        let start = driver.lamp.dropCenters[0]
        driver.drag(from: start, to: SIMD2(0.95, 0.5), seconds: 1)
        #expect(driver.lamp.dropSizes == [4])
    }

    @Test func partsDoNotMergeSoonAfterDivide() {
        var driver = swiped(beads: 4)
        driver.run(seconds: 2)
        #expect(driver.lamp.dropSizes.count == 2)
    }

    @Test func largeUntouchedDropDividesByItself() {
        var driver = Driver(lamp: LavaLamp(layout: [(center: SIMD2(0.5, 0.2), beads: 6)]))
        driver.run(seconds: 46)
        #expect(driver.lamp.dropSizes.count >= 2)
        #expect(driver.lamp.beadCount == 6)
    }

    @Test func groupsStayManyAndSmall() {
        var driver = Driver(lamp: LavaLamp())
        driver.run(seconds: 120)
        #expect(driver.lamp.dropSizes.count >= 8)
        #expect((driver.lamp.dropSizes.max() ?? 0) <= 5)
        let shown = driver.lamp.dropCenters.filter { $0.x > 0 && $0.x < 1 && $0.y > 0 && $0.y < 2.1 }
        #expect(shown.count >= driver.lamp.dropCenters.count / 2)
    }

    @Test func beadsInAGroupStayJoined() {
        var driver = Driver(lamp: LavaLamp())
        for _ in 0..<12 {
            driver.run(seconds: 10)
            #expect((driver.lamp.dropGaps.max() ?? 0) < 0.07)
        }
    }

    @Test func beadCountStaysTheSame() {
        var driver = Driver(lamp: LavaLamp())
        driver.run(seconds: 10)
        #expect(driver.lamp.beadCount == 41)
    }
}
