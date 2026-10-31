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
        let neck = bottom - keyHeight + 6
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

struct KeyLabel: View {
    let text: String
    let uppercase: Bool
    var scale: CGFloat = 1

    var body: some View {
        let lower = !uppercase && text.lowercased() == text && text.uppercased() != text
        Text(uppercase ? text.uppercased() : text)
            .font(.system(size: (lower ? 24 : 22) * scale))
            .offset(y: (lower ? -2 : -1.2) * scale)
    }
}

struct CharacterKey: View {
    static let space = "keys"

    private static let rise: CGFloat = 69
    private static let bodyHeight: CGFloat = 57
    private static let spread: CGFloat = 11.7
    private static let padding: CGFloat = 10
    private static let gap: CGFloat = 5

    let character: String
    let uppercase: Bool
    let variants: [String]
    let opensLeft: Bool
    var edge = KeyEdge.none
    var insets = EdgeInsets.key()
    var bounds: ClosedRange<CGFloat> = 0...0
    var isBlank = false
    let onInsert: (String) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false
    @State private var showsVariants = false
    @State private var choice = 0
    @State private var face = CGRect.zero
    @State private var hold: Task<Void, Never>?

    private var style: KeyStyle { .current(scheme) }
    private var options: [String] { [character] + variants }

    var body: some View {
        KeyLabel(text: character, uppercase: uppercase)
            .foregroundStyle(style.text)
            .opacity(isBlank || (pressed && !showsVariants) ? 0 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeyFace(color: style.key))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { face = $0 }
            .overlay(alignment: .topLeading) {
                if pressed && face.width > 0 {
                    if showsVariants {
                        panel
                    } else {
                        balloon
                    }
                }
            }
            .padding(insets)
            .contentShape(.rect)
            .zIndex(pressed ? 1 : 0)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        if !pressed {
                            pressed = true
                            UIDevice.current.playInputClick()
                            startHold()
                        }
                        if showsVariants {
                            choice = index(at: value.location.x)
                        }
                    }
                    .onEnded { _ in
                        hold?.cancel()
                        onInsert(showsVariants ? options[choice] : character)
                        pressed = false
                        showsVariants = false
                        choice = 0
                    }
            )
            .accessibilityLabel(uppercase ? character.uppercased() : character)
            .accessibilityAddTraits(.isKeyboardKey)
    }

    private var balloon: some View {
        let wide = Self.spread * 2
        let left = edge == .leading ? 0 : edge == .trailing ? wide : Self.spread
        let right = wide - left
        return KeyPopup(left: left, right: right, keyHeight: face.height, bodyHeight: Self.bodyHeight)
            .fill(style.popup)
            .overlay(alignment: .top) {
                KeyLabel(text: character, uppercase: uppercase, scale: 1.68)
                    .foregroundStyle(style.text)
                    .frame(height: 72)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: face.width + wide, height: face.height + Self.rise)
            .offset(x: -left, y: -Self.rise)
            .allowsHitTesting(false)
    }

    private var cell: CGSize {
        CGSize(width: face.width + 4, height: face.height - 1)
    }

    private var panelFrame: CGRect {
        let width = CGFloat(options.count) * cell.width + Self.padding * 2
        let height = cell.height + Self.padding * 2
        var minX = opensLeft
            ? face.midX + cell.width / 2 + Self.padding - width
            : face.midX - cell.width / 2 - Self.padding
        if bounds.upperBound > bounds.lowerBound {
            minX = min(max(minX, bounds.lowerBound), bounds.upperBound - width)
        }
        return CGRect(x: minX, y: face.minY - Self.gap - height, width: width, height: height)
    }

    private var panel: some View {
        let frame = panelFrame
        let ordered = opensLeft ? Array(options.enumerated().reversed()) : Array(options.enumerated())
        return HStack(spacing: 0) {
            ForEach(ordered, id: \.offset) { index, option in
                KeyLabel(text: option, uppercase: uppercase)
                    .foregroundStyle(index == choice ? Color.white : style.text)
                    .frame(width: cell.width, height: cell.height)
                    .background(index == choice ? KeyStyle.blue : .clear, in: .rect(cornerRadius: 9, style: .continuous))
            }
        }
        .padding(Self.padding)
        .background(style.popup, in: .rect(cornerRadius: 11, style: .continuous))
        .offset(x: frame.minX - face.minX, y: frame.minY - face.minY)
        .allowsHitTesting(false)
    }

    private func startHold() {
        guard !variants.isEmpty else { return }
        hold = Task {
            try? await Task.sleep(for: .milliseconds(370))
            guard !Task.isCancelled, pressed else { return }
            showsVariants = true
        }
    }

    private func index(at x: CGFloat) -> Int {
        guard cell.width > 0 else { return 0 }
        let frame = panelFrame
        let slot = Int(((x - frame.minX - Self.padding) / cell.width).rounded(.down))
        let clamped = min(max(slot, 0), options.count - 1)
        return opensLeft ? options.count - 1 - clamped : clamped
    }
}

struct FunctionKey<Label: View>: View {
    var isAction = false
    var insets = EdgeInsets.key()
    var isBlank = false
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    @ViewBuilder let label: (Bool) -> Label

    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false

    private var style: KeyStyle { .current(scheme) }

    private var fill: Color {
        if isAction { return pressed ? style.pressed : KeyStyle.blue }
        return pressed ? style.pressed : style.key
    }

    var body: some View {
        label(pressed)
            .foregroundStyle(isAction && !pressed ? Color.white : style.text)
            .opacity(isBlank ? 0 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeyFace(color: fill))
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

    let tag: String
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
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeyFace(color: pressed && !tracking ? style.pressed : style.key))
            .overlay(alignment: .bottomTrailing) {
                Text(tag)
                    .font(.system(size: 13).width(.condensed))
                    .foregroundStyle(style.tag)
                    .padding(.trailing, 6)
                    .padding(.bottom, 5)
                    .opacity(tracking ? 0 : 1)
            }
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
