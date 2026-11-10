import CoreGraphics
import Testing
@testable import QuietGPT

struct FieldRasterTests {
    private let size = CGSize(width: 200, height: 200)
    private let bead: [Float] = [0.5, 0.5, 0.15, 0, 0, 0.5, 1]

    private func update(_ raster: FieldRaster, beads: [Float], time: Float = 0) -> [(region: Int, image: CGImage)] {
        raster.update(beads: beads, unit: 200, origin: .zero, time: time, down: SIMD2(0, 1))
    }

    private func alpha(of image: CGImage) -> Int {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        var total = 0
        for offset in stride(from: 3, to: CFDataGetLength(data), by: 4) {
            total += Int(bytes[offset])
        }
        return total
    }

    private func totalAlpha(beads: [Float], mask: FieldMask = .none) -> Int {
        update(FieldRaster(size: size, mask: mask, dark: true), beads: beads).reduce(0) { $0 + alpha(of: $1.image) }
    }

    @Test func regionsCoverTheFullSize() {
        let raster = FieldRaster(size: size, mask: .none, dark: true)
        let union = raster.regions.reduce(CGRect.null) { $0.union($1.frame) }
        #expect(union.minX == 0)
        #expect(union.minY == 0)
        #expect(union.width >= size.width)
        #expect(union.height >= size.height)
    }

    @Test func firstFrameDrawsEveryRegion() {
        let raster = FieldRaster(size: size, mask: .none, dark: true)
        #expect(update(raster, beads: bead).count == raster.regions.count)
    }

    @Test func sameFrameChangesNothing() {
        let raster = FieldRaster(size: size, mask: .none, dark: true)
        _ = update(raster, beads: bead)
        #expect(update(raster, beads: bead).isEmpty)
    }

    @Test func smallMoveChangesOnlyNearbyRegions() {
        let raster = FieldRaster(size: size, mask: .none, dark: true)
        let small: [Float] = [0.2, 0.2, 0.03, 0, 0, 0.5, 1]
        _ = update(raster, beads: small)
        let moved: [Float] = [0.21, 0.2, 0.03, 0, 0, 0.5, 1]
        let changes = update(raster, beads: moved)
        #expect(!changes.isEmpty)
        #expect(changes.count < raster.regions.count / 2)
    }

    @Test func farChangesArriveInTheSameFrame() {
        let raster = FieldRaster(size: size, mask: .none, dark: true)
        let corners: [Float] = [0.1, 0.1, 0.03, 0, 0, 0.5, 1, 0.9, 0.9, 0.03, 0, 0, 0.5, 1]
        _ = update(raster, beads: [])
        let changes = update(raster, beads: corners)
        #expect(changes.contains { raster.regions[$0.region].frame.midX < 100 })
        #expect(changes.contains { raster.regions[$0.region].frame.midX > 100 })
        #expect(update(raster, beads: corners).isEmpty)
    }

    @Test func beadDrawsMoreInkThanEmptySpace() {
        #expect(totalAlpha(beads: bead) > totalAlpha(beads: []) * 2)
    }

    @Test func beadOffScreenDrawsOnlyTheGrid() {
        #expect(totalAlpha(beads: [9, 9, 0.15, 0, 0, 0.5, 1]) == totalAlpha(beads: []))
    }

    @Test func farLayerDrawsLessInk() {
        let far: [Float] = [0.5, 0.5, 0.15, 0, 0, 0.5, 0]
        let near: [Float] = [0.5, 0.5, 0.15, 0, 0, 0.5, 1]
        #expect(totalAlpha(beads: far) < totalAlpha(beads: near))
    }

    @Test func fadeLowersInk() {
        #expect(totalAlpha(beads: [], mask: .fadeDown) < totalAlpha(beads: [], mask: .none))
    }

    @Test func lightModeInkIsBlack() throws {
        let changes = update(FieldRaster(size: size, mask: .none, dark: false), beads: bead)
        for change in changes {
            let data = try #require(change.image.dataProvider?.data)
            let bytes = try #require(CFDataGetBytePtr(data))
            for offset in stride(from: 1, to: CFDataGetLength(data), by: 4) {
                #expect(bytes[offset] == 0)
            }
        }
    }
}
