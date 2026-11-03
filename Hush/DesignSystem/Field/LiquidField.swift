import SwiftUI

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

    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .global)
            TimelineView(.animation(minimumInterval: frameInterval, paused: reduceMotion)) { context in
                let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
                let touch = input.touch(at: context.date)
                Rectangle()
                    .colorEffect(ShaderLibrary.liquidGlass(
                        .float2(Float(frame.width), Float(frame.height)),
                        .float(Float(time)),
                        .float2(Float(input.tilt.x), Float(input.tilt.y)),
                        .float3(Float(touch.point.x - frame.minX), Float(touch.point.y - frame.minY), Float(touch.strength)),
                        .float(colorScheme == .dark ? 1 : 0),
                        .float(mode == .think ? 2.6 : 1),
                        .float(mode == .ripple ? 1 : 0)
                    ))
            }
        }
        .mask(maskShape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { input.start() }
        .onDisappear { input.stop() }
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
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.35), .init(color: .clear, location: 0.95)], startPoint: .top, endPoint: .bottom)
        case .fadeUp:
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.3), .init(color: .clear, location: 0.9)], startPoint: .bottom, endPoint: .top)
        case .vignette:
            EllipticalGradient(stops: [.init(color: .black, location: 0.3), .init(color: .clear, location: 0.8)])
        }
    }
}

#Preview {
    LiquidField(mode: .drift)
        .ignoresSafeArea()
}
