import SwiftUI

struct CharacterKey: View {
    let character: String
    let uppercase: Bool
    let variants: [String]
    let opensLeft: Bool
    let onInsert: (String) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false
    @State private var showsVariants = false
    @State private var choice = 0
    @State private var width: CGFloat = 0
    @State private var hold: Task<Void, Never>?

    private var style: KeyStyle { .current(scheme) }

    private func shown(_ value: String) -> String {
        uppercase ? value.uppercased() : value
    }

    var body: some View {
        Text(shown(character))
            .font(.system(size: 22))
            .foregroundStyle(style.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeyFace(color: style.key, shadow: style.shadow))
            .overlay(alignment: opensLeft ? .bottomTrailing : .bottomLeading) {
                if showsVariants {
                    variantStrip
                } else if pressed {
                    bubble
                }
            }
            .zIndex(pressed ? 1 : 0)
            .contentShape(.rect)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !pressed {
                            pressed = true
                            startHold()
                        }
                        if showsVariants {
                            choice = index(at: value.location.x)
                        }
                    }
                    .onEnded { _ in
                        hold?.cancel()
                        onInsert(showsVariants ? variants[choice] : character)
                        pressed = false
                        showsVariants = false
                        choice = 0
                    }
            )
            .accessibilityLabel(shown(character))
            .accessibilityAddTraits(.isKeyboardKey)
    }

    private var bubble: some View {
        Text(shown(character))
            .font(.system(size: 32))
            .foregroundStyle(style.text)
            .frame(width: width + 14, height: 52)
            .background(KeyFace(color: style.key, shadow: style.shadow))
            .offset(x: opensLeft ? 7 : -7, y: -50)
            .allowsHitTesting(false)
    }

    private var variantStrip: some View {
        let ordered = opensLeft ? Array(variants.enumerated().reversed()) : Array(variants.enumerated())
        return HStack(spacing: 0) {
            ForEach(ordered, id: \.offset) { index, variant in
                Text(shown(variant))
                    .font(.system(size: 24))
                    .frame(width: width, height: 46)
                    .foregroundStyle(index == choice ? Color.white : style.text)
                    .background(index == choice ? Color.accentColor : .clear, in: .rect(cornerRadius: 5))
            }
        }
        .padding(3)
        .background(KeyFace(color: style.key, shadow: style.shadow))
        .offset(x: opensLeft ? 3 : -3, y: -52)
        .allowsHitTesting(false)
    }

    private func startHold() {
        guard !variants.isEmpty else { return }
        hold = Task {
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled, pressed else { return }
            showsVariants = true
        }
    }

    private func index(at x: CGFloat) -> Int {
        guard width > 0 else { return 0 }
        let offset = opensLeft ? width - x : x
        return min(max(Int((offset / width).rounded(.down)), 0), variants.count - 1)
    }
}

struct FunctionKey<Label: View>: View {
    var isAction = false
    var isLight = false
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    @ViewBuilder let label: Label

    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false

    private var style: KeyStyle { .current(scheme) }

    private var fill: Color {
        if isAction { return pressed ? style.special : .accentColor }
        if isLight { return pressed ? style.special : style.key }
        return pressed ? style.key : style.special
    }

    var body: some View {
        label
            .foregroundStyle(isAction && !pressed ? Color.white : style.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeyFace(color: fill, shadow: style.shadow))
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        onPress()
                    }
                    .onEnded { _ in
                        pressed = false
                        onRelease()
                    }
            )
            .accessibilityAddTraits(.isKeyboardKey)
    }
}
