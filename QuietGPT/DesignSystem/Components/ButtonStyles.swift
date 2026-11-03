import SwiftUI

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BrandFont.font(.body, weight: .medium))
            .foregroundStyle(palette.onPrimary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(palette.primary, in: .capsule)
            .overlay {
                Capsule()
                    .fill(palette.onPrimary.opacity(configuration.isPressed ? 0.08 : 0))
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    var color: Color?

    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QuietGPTFont.callout)
            .foregroundStyle(color ?? palette.text2)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.capsule)
            .opacity(configuration.isPressed ? 0.5 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

struct CircleIconButtonStyle: ButtonStyle {
    var filled = false

    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(palette.text)
            .frame(width: 44, height: 44)
            .background(filled ? palette.raised : .clear, in: .circle)
            .contentShape(.circle)
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}
