import SwiftUI
import UIKit

enum KeyEdge {
    case none
    case leading
    case trailing
}

struct KeyPopup: Shape {
    var left: CGFloat
    var right: CGFloat
    var keyHeight: CGFloat
    var bodyHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        let small = KeyFace.radius
        let large: CGFloat = 11
        let x0 = rect.minX + left
        let x1 = rect.maxX - right
        let bottom = rect.maxY
        let neck = bottom - keyHeight + min(12, keyHeight / 3)
        let wide = rect.minY + bodyHeight
        let middle = (neck + wide) / 2

        var path = Path()
        path.move(to: CGPoint(x: x0 + small, y: bottom))
        path.addLine(to: CGPoint(x: x1 - small, y: bottom))
        path.addQuadCurve(to: CGPoint(x: x1, y: bottom - small), control: CGPoint(x: x1, y: bottom))
        path.addLine(to: CGPoint(x: x1, y: neck))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: wide),
            control1: CGPoint(x: x1, y: middle),
            control2: CGPoint(x: rect.maxX, y: middle)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + large))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - large, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + large, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + large), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: wide))
        path.addCurve(
            to: CGPoint(x: x0, y: neck),
            control1: CGPoint(x: rect.minX, y: middle),
            control2: CGPoint(x: x0, y: middle)
        )
        path.addLine(to: CGPoint(x: x0, y: bottom - small))
        path.addQuadCurve(to: CGPoint(x: x0 + small, y: bottom), control: CGPoint(x: x0, y: bottom))
        path.closeSubpath()
        return path
    }
}

struct CharacterKey: View {
    private static let rise: CGFloat = 58
    private static let bodyHeight: CGFloat = 52
    private static let spread: CGFloat = 12
    private static let margin: CGFloat = 5

    let character: String
    let uppercase: Bool
    let variants: [String]
    let opensLeft: Bool
    var edge = KeyEdge.none
    var insets = EdgeInsets.key()
    var isBlank = false
    let onInsert: (String) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false
    @State private var showsVariants = false
    @State private var choice = 0
    @State private var face = CGSize.zero
    @State private var hold: Task<Void, Never>?

    private var style: KeyStyle { .current(scheme) }

    private func shown(_ value: String) -> String {
        uppercase ? value.uppercased() : value
    }

    var body: some View {
        Text(shown(character))
            .font(.system(size: 22.5))
            .foregroundStyle(style.text)
            .opacity(isBlank ? 0 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeyFace(color: style.key, shadow: style.shadow))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { face = $0 }
            .overlay(alignment: .bottom) {
                if pressed && face != .zero {
                    popup
                }
            }
            .padding(insets)
            .contentShape(.rect)
            .zIndex(pressed ? 1 : 0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !pressed {
                            pressed = true
                            UIDevice.current.playInputClick()
                            startHold()
                        }
                        if showsVariants {
                            choice = index(at: value.location.x - insets.leading)
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

    private var extents: (left: CGFloat, right: CGFloat) {
        guard showsVariants else {
            return (
                edge == .leading ? 0 : Self.spread,
                edge == .trailing ? 0 : Self.spread
            )
        }
        let wide = max(CGFloat(variants.count) * face.width + Self.margin * 2, face.width + Self.spread * 2)
        let extra = wide - face.width
        return opensLeft ? (extra - Self.margin, Self.margin) : (Self.margin, extra - Self.margin)
    }

    private var popup: some View {
        let extents = extents
        return KeyPopup(left: extents.left, right: extents.right, keyHeight: face.height, bodyHeight: Self.bodyHeight)
            .fill(style.key)
            .shadow(color: style.shadow.opacity(0.6), radius: 1.5, x: 0, y: 1)
            .overlay(alignment: .top) {
                Group {
                    if showsVariants {
                        variantStrip
                    } else {
                        Text(shown(character))
                            .font(.system(size: 40))
                            .foregroundStyle(style.text)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.bodyHeight)
            }
            .frame(width: face.width + extents.left + extents.right, height: face.height + Self.rise)
            .offset(x: (extents.right - extents.left) / 2)
            .allowsHitTesting(false)
    }

    private var variantStrip: some View {
        let ordered = opensLeft ? Array(variants.enumerated().reversed()) : Array(variants.enumerated())
        return HStack(spacing: 0) {
            ForEach(ordered, id: \.offset) { index, variant in
                Text(shown(variant))
                    .font(.system(size: 25))
                    .frame(width: face.width, height: Self.bodyHeight - 10)
                    .foregroundStyle(index == choice ? Color.white : style.text)
                    .background(index == choice ? Color.accentColor : .clear, in: .rect(cornerRadius: 7, style: .continuous))
            }
        }
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
        guard face.width > 0 else { return 0 }
        let extents = extents
        let wide = face.width + extents.left + extents.right
        let start = (wide - CGFloat(variants.count) * face.width) / 2
        let slot = Int(((x + extents.left - start) / face.width).rounded(.down))
        let clamped = min(max(slot, 0), variants.count - 1)
        return opensLeft ? variants.count - 1 - clamped : clamped
    }
}

struct FunctionKey<Label: View>: View {
    var isAction = false
    var isLight = false
    var insets = EdgeInsets.key()
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
            .padding(insets)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        UIDevice.current.playInputClick()
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

struct SpaceKey: View {
    private static let step: CGFloat = 9

    let title: String
    let onSpace: () -> Void
    let onTrackpad: (Bool) -> Void
    let onMove: (Int) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false
    @State private var tracking = false
    @State private var moved: CGFloat = 0
    @State private var latest: CGFloat = 0
    @State private var hold: Task<Void, Never>?

    private var style: KeyStyle { .current(scheme) }

    var body: some View {
        Text(title)
            .font(.system(size: 16))
            .foregroundStyle(style.text)
            .opacity(tracking ? 0 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeyFace(color: pressed && !tracking ? style.special : style.key, shadow: style.shadow))
            .padding(.key())
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        latest = value.translation.width
                        if !pressed {
                            pressed = true
                            UIDevice.current.playInputClick()
                            hold = Task {
                                try? await Task.sleep(for: .milliseconds(380))
                                guard !Task.isCancelled, pressed else { return }
                                startTracking()
                            }
                        }
                        if !tracking, abs(latest) > 14 {
                            startTracking()
                        }
                        guard tracking else { return }
                        let steps = Int(((latest - moved) / Self.step).rounded(.towardZero))
                        if steps != 0 {
                            onMove(steps)
                            moved += CGFloat(steps) * Self.step
                        }
                    }
                    .onEnded { _ in
                        hold?.cancel()
                        if tracking {
                            tracking = false
                            onTrackpad(false)
                        } else {
                            onSpace()
                        }
                        pressed = false
                    }
            )
            .animation(.easeOut(duration: 0.15), value: tracking)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isKeyboardKey)
    }

    private func startTracking() {
        guard !tracking else { return }
        tracking = true
        moved = latest
        onTrackpad(true)
    }
}
