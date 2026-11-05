import CoreGraphics
import simd
import Foundation
import UIKit

final class FieldRaster {
    static let scale: CGFloat = 2

    struct Region {
        let frame: CGRect
        let columns: Range<Int>
        let rows: Range<Int>
        let context: CGContext?
    }

    private struct Tile {
        var columns: [Int] = []
        var rows: [Int] = []
        var strengths: [UInt32] = []
    }

    private static let threshold: Float = 0.32
    private static let gridValue: Float = 0.1
    private static let smallestInk: Float = 0.12
    private static let farInk: Float = 0.5
    private static let warpReach: Float = 0.03
    private static let regionCells = 12
    private static let commitBaseCost = 1.3
    private static let commitAreaCost = 3.6
    private static let costPerSecond = 75.0
    private static let maxCommitCost = 3.0
    private static let maxDebt = -6.0
    private static let maxWaitFrames = 15
    private static let tiles = makeTiles()

    let size: CGSize
    let regions: [Region]

    private let dark: Bool
    private let columns: Int
    private let rows: Int
    private let pixelWidth: Int
    private let pixelHeight: Int
    private let left: [Int]
    private let top: [Int]
    private let fade: [UInt32]
    private let regionOfCell: [Int]
    private let glyphs: UnsafeMutablePointer<UInt8>
    private let field: UnsafeMutablePointer<Float>
    private let height: UnsafeMutablePointer<Float>
    private let slopeX: UnsafeMutablePointer<Float>
    private let slopeY: UnsafeMutablePointer<Float>
    private let layerOfCell: UnsafeMutablePointer<Float>
    private let screenArea: CGFloat
    private var firstFrame = true
    private var budget = FieldRaster.maxCommitCost
    private var frameNumber = 0
    private var waitingSince: [Int: Int] = [:]

    var waitingCount: Int {
        waitingSince.count
    }

    init(size: CGSize, screen: CGSize, mask: FieldMask, dark: Bool) {
        self.size = size
        self.dark = dark
        screenArea = max(1, screen.width * screen.height)
        let cell = AsciiGlyphs.cell
        let columns = max(1, Int((size.width / cell.width).rounded(.up)))
        let rows = max(1, Int((size.height / cell.height).rounded(.up)))
        let pixelWidth = max(1, Int((size.width * Self.scale).rounded(.up)))
        let pixelHeight = max(1, Int((size.height * Self.scale).rounded(.up)))
        let left = (0..<columns).map { Int((CGFloat($0) * cell.width * Self.scale).rounded(.down)) }
        let top = (0..<rows).map { Int((CGFloat($0) * cell.height * Self.scale).rounded(.down)) }
        self.columns = columns
        self.rows = rows
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.left = left
        self.top = top

        var regions: [Region] = []
        var regionOfCell = [Int](repeating: 0, count: columns * rows)
        for firstRow in stride(from: 0, to: rows, by: Self.regionCells) {
            let rowRange = firstRow..<min(rows, firstRow + Self.regionCells)
            let pixelTop = top[firstRow]
            let pixelBottom = rowRange.upperBound < rows ? top[rowRange.upperBound] : pixelHeight
            for firstColumn in stride(from: 0, to: columns, by: Self.regionCells) {
                let columnRange = firstColumn..<min(columns, firstColumn + Self.regionCells)
                let pixelLeft = left[firstColumn]
                let pixelRight = columnRange.upperBound < columns ? left[columnRange.upperBound] : pixelWidth
                let width = max(1, pixelRight - pixelLeft)
                let height = max(1, pixelBottom - pixelTop)
                for row in rowRange {
                    for column in columnRange {
                        regionOfCell[row * columns + column] = regions.count
                    }
                }
                regions.append(Region(
                    frame: CGRect(
                        x: CGFloat(pixelLeft) / Self.scale,
                        y: CGFloat(pixelTop) / Self.scale,
                        width: CGFloat(width) / Self.scale,
                        height: CGFloat(height) / Self.scale
                    ),
                    columns: columnRange,
                    rows: rowRange,
                    context: CGContext(
                        data: nil,
                        width: width,
                        height: height,
                        bitsPerComponent: 8,
                        bytesPerRow: width * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
                    )
                ))
            }
        }
        self.regions = regions
        self.regionOfCell = regionOfCell

        var levels = [UInt32](repeating: 0, count: columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let x = (Double(column) + 0.5) / Double(columns)
                let y = (Double(row) + 0.5) / Double(rows)
                levels[row * columns + column] = UInt32(Self.fadeLevel(mask, x: x, y: y) * 256)
            }
        }
        fade = levels

        let count = columns * rows
        glyphs = .allocate(capacity: count)
        glyphs.initialize(repeating: 0, count: count)
        field = .allocate(capacity: count)
        height = .allocate(capacity: count)
        slopeX = .allocate(capacity: count)
        slopeY = .allocate(capacity: count)
        layerOfCell = .allocate(capacity: count)
    }

    deinit {
        glyphs.deallocate()
        field.deallocate()
        height.deallocate()
        slopeX.deallocate()
        slopeY.deallocate()
        layerOfCell.deallocate()
    }

    func update(beads: [Float], unit: Float, origin: CGPoint, time: Float, down: SIMD2<Float>, elapsed: Double, focus: CGPoint?, share: Double = 1) -> [(region: Int, image: CGImage)] {
        accumulate(beads: beads, unit: unit, originX: Float(origin.x), originY: Float(origin.y), time: time)
        frameNumber += 1
        for region in classify(down: down) where waitingSince[region] == nil {
            waitingSince[region] = frameNumber
        }
        budget = min(Self.maxCommitCost, budget + elapsed * Self.costPerSecond * share)

        let chosen: [Int]
        if firstFrame {
            firstFrame = false
            chosen = Array(regions.indices)
        } else {
            chosen = pickRegions(focus: focus)
        }
        for region in chosen {
            waitingSince[region] = nil
        }
        return chosen.compactMap { index in
            render(region: index).map { (index, $0) }
        }
    }

    private func pickRegions(focus: CGPoint?) -> [Int] {
        guard let anchor = anchorRegion(focus: focus) else { return [] }
        let overdue = waitingSince.filter { frameNumber - $0.value >= Self.maxWaitFrames }.keys.filter { $0 != anchor }
        var box = overdue.reduce(regions[anchor].frame) { $0.union(regions[$1].frame) }
        guard !overdue.isEmpty || cost(of: box) <= budget else { return [] }

        let center = CGPoint(x: box.midX, y: box.midY)
        let others = waitingSince.keys
            .filter { $0 != anchor && !overdue.contains($0) }
            .map { (region: $0, distance: distance(from: center, to: regions[$0].frame)) }
            .sorted { ($0.distance, $0.region) < ($1.distance, $1.region) }

        var chosen = [anchor] + overdue
        for other in others {
            let grown = box.union(regions[other.region].frame)
            guard cost(of: grown) <= budget else { continue }
            box = grown
            chosen.append(other.region)
        }
        budget = max(Self.maxDebt, budget - cost(of: box))
        return chosen
    }

    private func anchorRegion(focus: CGPoint?) -> Int? {
        if let focus {
            return waitingSince.keys.min { first, second in
                let a = distance(from: focus, to: regions[first].frame)
                let b = distance(from: focus, to: regions[second].frame)
                return (a, first) < (b, second)
            }
        }
        return waitingSince.min { ($0.value, $0.key) < ($1.value, $1.key) }?.key
    }

    private func distance(from point: CGPoint, to frame: CGRect) -> CGFloat {
        hypot(frame.midX - point.x, frame.midY - point.y)
    }

    private func cost(of box: CGRect) -> Double {
        Self.commitBaseCost + Self.commitAreaCost * Double(box.width * box.height / screenArea)
    }

    private func accumulate(beads: [Float], unit: Float, originX: Float, originY: Float, time: Float) {
        let cellWidth = Float(AsciiGlyphs.cell.width)
        let cellHeight = Float(AsciiGlyphs.cell.height)
        let count = columns * rows
        field.update(repeating: 0, count: count)
        height.update(repeating: 0, count: count)
        slopeX.update(repeating: 0, count: count)
        slopeY.update(repeating: 0, count: count)
        layerOfCell.update(repeating: 0, count: count)

        var index = 0
        while index + LavaLamp.stride - 1 < beads.count {
            let beadX = beads[index]
            let beadY = beads[index + 1]
            let reach = beads[index + 2] * 1.8
            let velocityX = beads[index + 3]
            let velocityY = beads[index + 4]
            let lobe = 0.55 + 0.45 * beads[index + 5]
            let layer = beads[index + 6]
            index += LavaLamp.stride

            let inverse = 1 / (reach * reach)
            let speed = (velocityX * velocityX + velocityY * velocityY).squareRoot()
            let stretch = 1 + min(0.9, speed * 4)
            let thin = stretch.squareRoot()
            let alongX = speed > 1e-4 ? velocityX / speed : 0
            let alongY = speed > 1e-4 ? velocityY / speed : 1
            let bound = reach * stretch + Self.warpReach

            let lowColumn = ((beadX - bound) * unit - originX) / cellWidth
            let highColumn = ((beadX + bound) * unit - originX) / cellWidth
            let lowRow = ((beadY - bound) * unit - originY) / cellHeight
            let highRow = ((beadY + bound) * unit - originY) / cellHeight
            guard highColumn >= 0, highRow >= 0, lowColumn < Float(columns), lowRow < Float(rows) else { continue }

            for row in max(0, Int(lowRow))...min(rows - 1, Int(highRow)) {
                let pointY = ((Float(row) + 0.5) * cellHeight + originY) / unit
                for column in max(0, Int(lowColumn))...min(columns - 1, Int(highColumn)) {
                    let pointX = ((Float(column) + 0.5) * cellWidth + originX) / unit
                    let warpX = (sin(pointY * 9 + time * 0.23) + 0.5 * sin(pointY * 17 - pointX * 7 - time * 0.31)) * 0.012
                    let warpY = (sin(pointX * 11 - time * 0.19) + 0.5 * sin(pointX * 19 + pointY * 6 + time * 0.27)) * 0.012
                    let distanceX = pointX + warpX - beadX
                    let distanceY = pointY + warpY - beadY
                    let a = (distanceX * alongX + distanceY * alongY) / stretch
                    let b = (distanceY * alongX - distanceX * alongY) * thin
                    let u = (a * a + b * b) * inverse
                    guard u < 1 else { continue }
                    let k = 1 - u
                    let k3 = k * k * k
                    let cell = row * columns + column
                    if layerOfCell[cell] != layer {
                        guard field[cell] == 0 || k3 >= field[cell] else { continue }
                        field[cell] = 0
                        height[cell] = 0
                        slopeX[cell] = 0
                        slopeY[cell] = 0
                        layerOfCell[cell] = layer
                    }
                    field[cell] += k3
                    height[cell] += lobe * k3 * k3
                    let weight = 2 * inverse * lobe * 6 * k3 * k * k
                    slopeX[cell] -= (alongX * a / stretch - alongY * b * thin) * weight
                    slopeY[cell] -= (alongY * a / stretch + alongX * b * thin) * weight
                }
            }
        }
    }

    private func classify(down: SIMD2<Float>) -> Set<Int> {
        let tiles = Self.tiles
        let light = simd_normalize(SIMD3<Float>(-0.45 - down.x * 0.5, -down.y * 0.55 - 0.25, 0.7))
        let halfway = simd_normalize(light + SIMD3<Float>(0, 0, 1))
        let levels = Float(tiles.count) - 0.01
        var dirty = Set<Int>()

        for row in 0..<rows {
            for column in 0..<columns {
                let cell = row * columns + column
                let value: Float
                if field[cell] >= Self.threshold {
                    value = max(Self.smallestInk, shade(cell: cell, light: light, halfway: halfway) * (Self.farInk + (1 - Self.farInk) * layerOfCell[cell]))
                } else if column % 4 == 0, row % 3 == 0 {
                    value = Self.gridValue
                } else {
                    value = 0
                }
                let glyph = UInt8(min(tiles.count - 1, Int(value * levels)))
                if glyph != glyphs[cell] {
                    glyphs[cell] = glyph
                    dirty.insert(regionOfCell[cell])
                }
            }
        }
        return dirty
    }

    private func render(region index: Int) -> CGImage? {
        let region = regions[index]
        guard let context = region.context, let data = context.data else { return nil }
        let pixels = data.assumingMemoryBound(to: UInt32.self)
        let width = context.width
        let height = context.height
        memset(data, 0, width * height * 4)
        let originX = left[region.columns.lowerBound]
        let originY = top[region.rows.lowerBound]
        let tiles = Self.tiles

        for row in region.rows {
            for column in region.columns {
                let cell = row * columns + column
                let glyph = Int(glyphs[cell])
                guard glyph > 0 else { continue }
                let level = fade[cell]
                let tile = tiles[glyph]
                for slot in tile.strengths.indices {
                    let x = left[column] - originX + tile.columns[slot]
                    let y = top[row] - originY + tile.rows[slot]
                    guard x < width, y < height else { continue }
                    let alpha = (tile.strengths[slot] * level) >> 8
                    pixels[y * width + x] = dark ? alpha << 24 | alpha << 16 | alpha << 8 | alpha : alpha << 24
                }
            }
        }
        return context.makeImage()
    }

    private func shade(cell: Int, light: SIMD3<Float>, halfway: SIMD3<Float>) -> Float {
        let normal = simd_normalize(SIMD3<Float>(-slopeX[cell] * 0.022, -slopeY[cell] * 0.022, 1))
        let diffuse = max(simd_dot(normal, light), 0)
        let shine = max(simd_dot(normal, halfway), 0)
        let shine2 = shine * shine
        let shine4 = shine2 * shine2
        let gloss = shine4 * shine4 * shine4 * shine2
        let t = min(1, max(0, (height[cell] - 0.08) / 0.67))
        let crease = t * t * (3 - 2 * t)
        return min(1, max(0, 0.12 + crease * (0.18 + 0.42 * diffuse) + 0.4 * gloss * crease))
    }

    private static func fadeLevel(_ mask: FieldMask, x: Double, y: Double) -> Double {
        switch mask {
        case .none:
            1
        case .fadeDown:
            ramp(y, from: 0.35, to: 0.95, low: 0.35)
        case .fadeUp:
            ramp(1 - y, from: 0.3, to: 0.9, low: 0.35)
        case .vignette:
            ramp((pow((x - 0.5) * 2, 2) + pow((y - 0.5) * 2, 2)).squareRoot(), from: 0.3, to: 0.85, low: 0.4)
        }
    }

    private static func ramp(_ value: Double, from start: Double, to end: Double, low: Double) -> Double {
        let t = min(1, max(0, (value - start) / (end - start)))
        return 1 + (low - 1) * t
    }

    private static func makeTiles() -> [Tile] {
        let cell = AsciiGlyphs.cell
        let width = Int((cell.width * scale).rounded(.up))
        let height = Int((cell.height * scale).rounded(.up))
        let font = UIFont.monospacedSystemFont(ofSize: AsciiGlyphs.fontSize, weight: AsciiGlyphs.weight)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let count = AsciiGlyphs.ramp.count

        return AsciiGlyphs.ramp.enumerated().map { index, character in
            var tile = Tile()
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return tile }

            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: scale, y: -scale)
            UIGraphicsPushContext(context)
            let text = String(character) as NSString
            let bounds = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (cell.width - bounds.width) / 2, y: (cell.height - bounds.height) / 2), withAttributes: attributes)
            UIGraphicsPopContext()

            guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return tile }
            let strength = 0.12 + 0.32 * (Float(index) + 0.5) / Float(count)
            for y in 0..<height {
                for x in 0..<width where data[y * width + x] > 0 {
                    tile.columns.append(x)
                    tile.rows.append(y)
                    tile.strengths.append(UInt32(Float(data[y * width + x]) * strength))
                }
            }
            return tile
        }
    }
}
