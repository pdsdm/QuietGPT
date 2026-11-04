import SwiftUI
import UIKit

struct TopRow: View {
    private enum Item: Identifiable, Equatable {
        case undo
        case style(RewriteStyle, isPerson: Bool)
        case ask

        var id: String {
            switch self {
            case .undo: "undo"
            case .style(let value, _): value.id.uuidString
            case .ask: KeyboardOptions.topRowAsk
            }
        }
    }

    let model: KeyboardModel
    let actions: BarActions

    @Environment(\.colorScheme) private var scheme

    private var style: KeyStyle { .current(scheme) }

    private var tagHeight: CGFloat {
        min(30, CGFloat(model.options.topMargin) - 6)
    }

    private var items: [Item] {
        let chosen = Set(model.options.topRow)
        let people = model.people.filter { chosen.contains($0.id.uuidString) }.map { Item.style($0, isPerson: true) }
        let styles = model.styles.filter { chosen.contains($0.id.uuidString) }.map { Item.style($0, isPerson: false) }
        let undo = model.canUndo && !model.isWriting ? [Item.undo] : []
        let ask = chosen.contains(KeyboardOptions.topRowAsk) && model.showsAsk ? [Item.ask] : []
        return undo + people + styles + ask
    }

    var body: some View {
        HStack(spacing: 4) {
            logo
            if let hint = model.hint {
                Text(hint)
                    .font(BrandFont.font(size: 14))
                    .foregroundStyle(Color(style.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(items) { cell($0) }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.25), value: model.hint)
        .animation(.snappy(duration: 0.25), value: items)
        .animation(.snappy(duration: 0.25), value: model.active)
    }

    private var logo: some View {
        Button {
            UIDevice.current.playInputClick()
            actions.open()
        } label: {
            BarMark(style: style, size: 26)
                .frame(width: 40, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(BarPressStyle())
        .accessibilityLabel(BrandFont.name)
    }

    private func cell(_ item: Item) -> some View {
        let active = isActive(item)
        let dimmed = model.isWriting && !active
        return Button {
            tap(item)
        } label: {
            HStack(spacing: 5) {
                glyph(item)
                    .accessibilityHidden(true)
                Text(label(item))
                    .font(BrandFont.font(size: 14, weight: .medium))
                    .foregroundStyle(Color(style.text))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(height: tagHeight)
            .background(Color(style.key), in: .capsule)
            .overlay {
                Capsule().strokeBorder(active ? Color(style.accent) : Color(style.outline), lineWidth: active ? 1.5 : 0.5)
            }
            .frame(height: 40)
            .contentShape(.rect)
            .opacity(dimmed ? 0.4 : 1)
        }
        .buttonStyle(BarPressStyle())
        .disabled(dimmed)
    }

    @ViewBuilder
    private func glyph(_ item: Item) -> some View {
        switch item {
        case .undo:
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(style.text))
        case .style(let value, let isPerson):
            StyleGlyph(value: value, isPerson: isPerson, color: Color(style.text))
                .scaleEffect(0.85)
        case .ask:
            Image(systemName: "text.bubble")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(style.text))
        }
    }

    private func isActive(_ item: Item) -> Bool {
        if case .style(let value, _) = item { return value.id == model.active }
        return false
    }

    private func label(_ item: Item) -> String {
        switch item {
        case .undo: KeyboardText.string("Undo")
        case .style(let value, _): value.title
        case .ask: KeyboardText.string("Ask")
        }
    }

    private func tap(_ item: Item) {
        UIDevice.current.playInputClick()
        switch item {
        case .undo: actions.undo()
        case .ask: actions.ask()
        case .style(let value, _):
            if model.isWriting {
                actions.stop()
            } else {
                actions.rewrite(value)
            }
        }
    }
}
