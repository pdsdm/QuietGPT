import SwiftUI

struct StyleTile: View {
    let value: RewriteStyle
    let style: KeyStyle
    var isPerson = false
    var active = false
    var lit = false

    var body: some View {
        VStack(spacing: 8) {
            badge
            HStack(spacing: 3) {
                Text(value.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if lit {
                    Caret(color: Color(style.accent), height: 14)
                }
            }
            .font(BrandFont.font(size: 14, weight: .medium))
            .foregroundStyle(Color(style.text))
        }
        .padding(.horizontal, 4)
        .frame(width: 78, height: 86)
        .background(Color(style.key), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(active ? Color(style.accent) : Color(style.outline), lineWidth: active ? 1.5 : 0.5)
        }
    }

    private var badge: some View {
        let ink = Color(lit ? style.background : style.text)
        return ZStack {
            Circle()
                .fill(lit ? Color(style.text) : Color(style.lit).opacity(0.45))
            StyleGlyph(value: value, isPerson: isPerson, color: ink)
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }

}

struct StyleGlyph: View {
    let value: RewriteStyle
    var isPerson = false
    let color: Color

    var body: some View {
        if let code = isPerson ? value.initials : Self.codes[value.id] {
            Text(code)
                .font(BrandFont.font(size: 12, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(color)
        } else {
            Image(systemName: Self.symbols[value.id] ?? "pencil")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
        }
    }

    private static let symbols: [RewriteStyle.ID: String] = {
        let names = ["heart", "arrow.down.right.and.arrow.up.left", "arrow.up.left.and.arrow.down.right", "briefcase", "checkmark"]
        return Dictionary(uniqueKeysWithValues: zip(RewriteStyle.builtIn.prefix(5).map(\.id), names))
    }()

    private static let codes: [RewriteStyle.ID: String] = {
        Dictionary(uniqueKeysWithValues: zip(RewriteStyle.builtIn.dropFirst(5).map(\.id), ["EN", "ES"]))
    }()
}

struct Caret: View {
    var color: Color
    var height: CGFloat = 17

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: 2, height: height)
            .phaseAnimator([1.0, 0.1]) { content, phase in
                content.opacity(phase)
            } animation: { _ in
                .easeInOut(duration: 0.5)
            }
    }
}
