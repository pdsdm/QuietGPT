import SwiftUI
import UIKit

enum FieldMode: Equatable {
    case drift
    case ripple
    case think
}

enum FieldMask {
    case none
    case fadeDown
    case fadeUp
    case vignette
}

struct LiquidField: View {
    var mode: FieldMode = .drift
    var mask: FieldMask = .vignette
    var share: Double = 1

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let thinkShare = 0.35

    private let input = FieldInput.shared

    var body: some View {
        FieldCanvas(energy: energy, mask: mask, dark: colorScheme == .dark, paused: reduceMotion, share: mode == .think ? Self.thinkShare : share)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { input.start() }
            .onDisappear { input.stop() }
    }

    private var energy: Double {
        switch mode {
        case .drift: 1
        case .ripple: 1.4
        case .think: 2.6
        }
    }
}

private struct FieldCanvas: UIViewRepresentable {
    let energy: Double
    let mask: FieldMask
    let dark: Bool
    let paused: Bool
    let share: Double

    func makeUIView(context: Context) -> FieldCanvasView {
        FieldCanvasView()
    }

    func updateUIView(_ view: FieldCanvasView, context: Context) {
        view.configure(energy: energy, mask: mask, dark: dark, paused: paused, share: share)
    }
}

private final class FieldCanvasView: UIView {
    private static let restingFramesPerSecond: Float = 30
    private static let touchFramesPerSecond: Float = 60
    private static let lowPowerFramesPerSecond: Float = 30
    private static let slowestFramesPerSecond: Float = 15
    private static let physicsStep = 1.0 / 30
    private static let maxPhysicsSteps = 4
    private static let renderQueue = DispatchQueue(label: "com.pdsdm.quietgpt.field", qos: .userInitiated)

    private let input = FieldInput.shared
    private let lamp = LavaLamp.shared

    private var energy = 1.0
    private var fieldMask = FieldMask.vignette
    private var dark = false
    private var paused = false
    private var share = 1.0
    private var raster: FieldRaster?
    private var regionLayers: [CALayer] = []
    private var link: CADisplayLink?
    private var rate: Float = 0
    private var lastFrame: Date?
    private var rendering = false
    private var needsFrame = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func configure(energy: Double, mask: FieldMask, dark: Bool, paused: Bool, share: Double) {
        self.energy = energy
        self.share = share
        if fieldMask != mask {
            fieldMask = mask
            raster = nil
        }
        let redraw = self.dark != dark || self.paused != paused
        if self.dark != dark {
            raster = nil
        }
        self.dark = dark
        self.paused = paused
        updateLink()
        if redraw { draw(at: .now) }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateLink()
        if window != nil { draw(at: .now) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        draw(at: .now)
    }

    private func updateLink() {
        guard window != nil, !paused else {
            link?.invalidate()
            link = nil
            rate = 0
            lastFrame = nil
            return
        }
        var wanted = input.pressing
            ? Self.touchFramesPerSecond
            : min(Self.restingFramesPerSecond, max(Self.slowestFramesPerSecond, Self.restingFramesPerSecond * Float(share)))
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            wanted = min(wanted, Self.lowPowerFramesPerSecond)
        }
        if link == nil {
            let created = CADisplayLink(target: self, selector: #selector(tick))
            created.add(to: .main, forMode: .common)
            link = created
        }
        guard wanted != rate else { return }
        rate = wanted
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: wanted, maximum: wanted, preferred: wanted)
    }

    @objc private func tick(_ link: CADisplayLink) {
        updateLink()
        draw(at: .now)
    }

    private func draw(at date: Date) {
        guard let window, bounds.width > 0, bounds.height > 0 else { return }

        let screen = window.screen.bounds.size
        let scale = max(1, min(screen.width, screen.height))
        let extent = SIMD2(screen.width / scale, screen.height / scale)
        let finger = SIMD2(input.point.x / scale, input.point.y / scale)
        let start = lastFrame ?? date
        let elapsed = max(0, date.timeIntervalSince(start))
        let steps = max(1, min(Self.maxPhysicsSteps, Int((elapsed / Self.physicsStep).rounded(.up))))
        for step in 1...steps {
            lamp.step(
                to: start.addingTimeInterval(elapsed * Double(step) / Double(steps)),
                extent: extent,
                gravity: input.gravity,
                finger: finger,
                pressing: input.pressing,
                energy: energy
            )
        }
        lastFrame = date

        guard !rendering else {
            needsFrame = true
            return
        }
        if raster?.size != bounds.size {
            rebuildRaster()
        }
        guard let raster else { return }

        rendering = true
        needsFrame = false
        let beads = lamp.packed
        let unit = Float(scale)
        let origin = convert(bounds.origin, to: nil)
        let time = Float(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))
        let down = lamp.direction
        Self.renderQueue.async { [weak self] in
            let changes = raster.update(beads: beads, unit: unit, origin: origin, time: time, down: down)
            DispatchQueue.main.async {
                self?.show(changes, from: raster)
            }
        }
    }

    private func show(_ changes: [(region: Int, image: CGImage)], from source: FieldRaster) {
        rendering = false
        if source === raster, !changes.isEmpty {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for change in changes {
                regionLayers[change.region].contents = change.image
            }
            CATransaction.commit()
        }
        if needsFrame, link == nil {
            draw(at: .now)
        }
    }

    private func rebuildRaster() {
        let created = FieldRaster(size: bounds.size, mask: fieldMask, dark: dark)
        raster = created
        regionLayers.forEach { $0.removeFromSuperlayer() }
        regionLayers = created.regions.map { region in
            let tile = CALayer()
            tile.frame = region.frame
            tile.contentsGravity = .resize
            tile.contentsScale = FieldRaster.scale
            tile.actions = ["contents": NSNull()]
            layer.addSublayer(tile)
            return tile
        }
    }
}

#Preview {
    LiquidField(mode: .drift)
        .ignoresSafeArea()
}
