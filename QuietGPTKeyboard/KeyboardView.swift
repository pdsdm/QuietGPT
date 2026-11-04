import SwiftUI
import UIKit

struct QuietGPTBar: View {
    static let height: CGFloat = 34
    static let markWidth: CGFloat = 40

    private enum Item: Identifiable, Equatable {
        case undo
        case style(RewriteStyle)
        case ask

        var id: String {
            switch self {
            case .undo: "undo"
            case .style(let style): style.id.uuidString
            case .ask: "ask"
            }
        }
    }

    let model: KeyboardModel
    let actions: BarActions

    @Environment(\.colorScheme) private var scheme

    private var style: KeyStyle { .current(scheme) }

    private var items: [Item] {
        (model.canUndo && !model.isWriting ? [.undo] : []) + model.styles.map(Item.style) + (model.showsAsk ? [.ask] : [])
    }

    var body: some View {
        GeometryReader { geometry in
            let slot = (geometry.size.width - Self.markWidth) / 3
            HStack(spacing: 0) {
                Button {
                    UIDevice.current.playInputClick()
                    actions.open()
                } label: {
                    BarMark(style: style, size: 26)
                        .frame(width: Self.markWidth, height: Self.markWidth)
                        .contentShape(.rect)
                }
                .buttonStyle(BarPressStyle())
                .accessibilityLabel(BrandFont.name)
                .padding(.leading, 6)
                ZStack {
                    if model.isAsking {
                        askRow
                            .transition(.opacity.combined(with: .offset(y: 6)))
                    } else if let hint = model.hint {
                        Text(hint)
                            .font(BrandFont.font(size: 15))
                            .foregroundStyle(Color(style.secondary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity.combined(with: .offset(y: 6)))
                            .id(hint)
                    } else {
                        suggestions(slot: slot)
                            .transition(.opacity.combined(with: .offset(y: -6)))
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .offset(y: KeyLayout.topCenter(margin: geometry.size.height, strip: model.glassStrip) - geometry.size.height / 2)
        }
        .animation(.snappy(duration: 0.25), value: model.isAsking)
        .animation(.snappy(duration: 0.25), value: model.hint)
        .animation(.snappy(duration: 0.25), value: model.canUndo)
        .animation(.snappy(duration: 0.25), value: model.active)
        .animation(.snappy(duration: 0.25), value: model.styles)
    }

    private func suggestions(slot: CGFloat) -> some View {
        let all = items
        return ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(Array(all.enumerated()), id: \.element.id) { index, item in
                    cell(item, slot: slot)
                        .overlay(alignment: .trailing) {
                            if index < all.count - 1 && !isActive(item) && !isActive(all[index + 1]) {
                                Rectangle()
                                    .fill(Color(style.separator))
                                    .frame(width: 1, height: 24)
                            }
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollDisabled(all.count <= 3)
    }

    private func isActive(_ item: Item) -> Bool {
        if case .style(let value) = item { return value.id == model.active }
        return false
    }

    private func cell(_ item: Item, slot: CGFloat) -> some View {
        let active = isActive(item)
        let dimmed = model.isWriting && !active
        return Button {
            tap(item)
        } label: {
            HStack(spacing: 5) {
                switch item {
                case .undo:
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .medium))
                    Text(KeyboardText.string("Undo"))
                case .style(let value):
                    Text(value.title)
                    if active && model.isWriting {
                        Caret(color: Color(style.accent))
                            .transition(.scale.combined(with: .opacity))
                    }
                case .ask:
                    Image(systemName: "text.bubble")
                        .font(.system(size: 13, weight: .medium))
                    Text(KeyboardText.string("Ask"))
                }
            }
            .font(BrandFont.font(size: 16))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(Color(style.text))
            .padding(.horizontal, 6)
            .frame(width: slot - 4, height: 30)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: KeyStyle.radius, style: .continuous)
                        .fill(Color(style.key))
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .frame(width: slot, height: 38)
            .contentShape(.rect)
            .opacity(dimmed ? 0.4 : 1)
        }
        .buttonStyle(BarPressStyle())
        .disabled(dimmed)
        .accessibilityLabel(accessibility(item, active: active))
    }

    private func accessibility(_ item: Item, active: Bool) -> String {
        switch item {
        case .undo: "Undo rewrite"
        case .style(let value): active && model.isWriting ? "Stop \(value.title)" : "Rewrite \(value.title)"
        case .ask: "Tell QuietGPT how to rewrite"
        }
    }

    private func tap(_ item: Item) {
        UIDevice.current.playInputClick()
        switch item {
        case .undo: actions.undo()
        case .ask: actions.ask()
        case .style(let value):
            if model.isWriting {
                actions.stop()
            } else {
                actions.rewrite(value)
            }
        }
    }

    private var askRow: some View {
        HStack(spacing: 8) {
            Button {
                UIDevice.current.playInputClick()
                actions.ask()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(style.secondary))
                    .frame(width: 34, height: 34)
                    .contentShape(.rect)
            }
            .buttonStyle(BarPressStyle())
            .accessibilityLabel("Cancel instruction")

            HStack(spacing: 1) {
                if model.instruction.isEmpty {
                    Caret(color: Color(style.accent))
                    Text(KeyboardText.string("make it warmer and shorter"))
                        .foregroundStyle(Color(style.secondary))
                } else {
                    Text(model.instruction)
                        .foregroundStyle(Color(style.text))
                        .truncationMode(.head)
                    Caret(color: Color(style.accent))
                }
            }
            .font(BrandFont.font(size: 16))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                actions.submitAsk()
            } label: {
                Text(model.goTitle)
                    .font(BrandFont.font(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Color(KeyStyle.blue), in: .capsule)
            }
            .buttonStyle(BarPressStyle())
            .disabled(model.instruction.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(model.instruction.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
    }
}

struct BarMark: View {
    let style: KeyStyle
    var size: CGFloat = 24

    var body: some View {
        LockMark()
            .fill(Color(style.text))
            .frame(width: size * 0.84, height: size * 0.84)
            .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct BarPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}
