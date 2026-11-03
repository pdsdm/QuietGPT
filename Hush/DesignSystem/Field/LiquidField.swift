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

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let input = FieldInput.shared
    private let lamp = LavaLamp.shared

    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .global)
            let screen = screenSize(fallback: frame.size)
            let scale = max(1, min(screen.width, screen.height))
            TimelineView(.animation(minimumInterval: frameInterval, paused: reduceMotion)) { context in
                let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
                let touch = input.touch(at: context.date)
                let _ = lamp.step(
                    to: context.date,
                    extent: SIMD2(screen.width / scale, screen.height / scale),
                    gravity: input.gravity,
                    touch: SIMD3(touch.point.x / scale, touch.point.y / scale, touch.strength),
                    energy: energy
                )
                let pool = lamp.pool
                let finger = lamp.finger
                Rectangle()
                    .colorEffect(ShaderLibrary.lavaLamp(
                        .float2(Float(frame.minX), Float(frame.minY)),
                        .float(Float(scale)),
                        .float(Float(time)),
                        .floatArray(lamp.packed),
                        .float4(pool.x, pool.y, pool.z, pool.w),
                        .float3(finger.x, finger.y, finger.z),
                        .float(colorScheme == .dark ? 1 : 0),
                        .image(AsciiGlyphs.atlas),
                        .float(Float(AsciiGlyphs.ramp.count))
                    ))
            }
        }
        .mask(maskShape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { input.start() }
        .onDisappear { input.stop() }
    }

    private func screenSize(fallback: CGSize) -> CGSize {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.screen.bounds.size ?? fallback
    }

    private var energy: Double {
        switch mode {
        case .drift: 1
        case .ripple: 1.4
        case .think: 2.6
        }
    }

    private var frameInterval: TimeInterval {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? 1.0 / 30 : 1.0 / 60
    }

    @ViewBuilder
    private var maskShape: some View {
        switch mask {
        case .none:
            Rectangle()
        case .fadeDown:
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.35), .init(color: .black.opacity(0.35), location: 0.95)], startPoint: .top, endPoint: .bottom)
        case .fadeUp:
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.3), .init(color: .black.opacity(0.35), location: 0.9)], startPoint: .bottom, endPoint: .top)
        case .vignette:
            EllipticalGradient(stops: [.init(color: .black, location: 0.3), .init(color: .black.opacity(0.4), location: 0.85)])
        }
    }
}

#Preview {
    LiquidField(mode: .drift)
        .ignoresSafeArea()
}
