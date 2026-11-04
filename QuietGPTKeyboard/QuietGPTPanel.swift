import SwiftUI

struct QuietGPTPanel: View {
    let model: KeyboardModel
    let actions: BarActions

    @Environment(\.colorScheme) private var scheme

    private var style: KeyStyle { .current(scheme) }

    var body: some View {
        VStack(spacing: 8) {
            header
                .padding(.horizontal, 12)
            rail
            if model.showsAsk {
                askField
                    .padding(.horizontal, 12)
            }
            settings
                .padding(.horizontal, 12)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topLeading) {
            closeButton
        }
        .animation(.snappy(duration: 0.25), value: model.isWriting)
        .animation(.snappy(duration: 0.25), value: model.canUndo)
        .animation(.snappy(duration: 0.25), value: model.hint)
        .animation(.snappy(duration: 0.25), value: model.options)
    }

    private var header: some View {
        HStack(spacing: 8) {
            BarMark(style: style, size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(BrandFont.name)
                    .font(BrandFont.wordmark(size: 17))
                    .tracking(-0.4)
                    .foregroundStyle(Color(style.text))
                Text(status)
                    .font(BrandFont.font(size: 11))
                    .foregroundStyle(Color(style.secondary))
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            if model.isWriting {
                pill(KeyboardText.string("Stop"), symbol: "stop.fill", filled: true, action: actions.stop)
            } else if model.canUndo {
                pill(KeyboardText.string("Undo"), symbol: "arrow.uturn.backward", action: actions.undo)
            }
        }
        .frame(minHeight: 36)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var closeButton: some View {
        let frame = model.closeFrame
        return Button {
            UIDevice.current.playInputClick()
            actions.close()
        } label: {
            Image(systemName: "keyboard")
                .font(.system(size: 19))
                .foregroundStyle(Color(style.text))
                .frame(width: frame.width, height: frame.height)
                .background(Color(style.key), in: .rect(cornerRadius: KeyStyle.radius, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(BarPressStyle())
        .accessibilityLabel(KeyboardText.string("Back to letters"))
        .position(x: frame.midX, y: frame.midY)
    }

    private var status: String {
        if let hint = model.hint { return hint }
        if model.isWriting { return KeyboardText.string("rewriting…") }
        let place = KeyboardText.string("on this iPhone")
        switch model.ruleCount {
        case 0: return place
        case 1: return "\(place) · \(KeyboardText.string("1 rule"))"
        case let count: return "\(place) · \(KeyboardText.string("\(count) rules"))"
        }
    }

    private var rail: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.people) { value in
                    tile(value, isPerson: true, active: model.active == value.id) {
                        actions.rewrite(value)
                    }
                }
                ForEach(model.styles) { value in
                    tile(value, active: model.active == value.id) {
                        actions.rewrite(value)
                    }
                }
            }
        }
        .contentMargins(.leading, 12, for: .scrollContent)
        .contentMargins(.trailing, 32, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .scrollClipDisabled()
        .scrollEdgeEffectHidden(true, for: .all)
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0.82), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
                .padding(.vertical, -20)
                .ignoresSafeArea()
        }
        .frame(height: 86)
    }

    private func tile(_ value: RewriteStyle, isPerson: Bool = false, active: Bool, action: @escaping () -> Void) -> some View {
        let dimmed = model.isWriting && !active
        return Button {
            UIDevice.current.playInputClick()
            action()
        } label: {
            StyleTile(value: value, style: style, isPerson: isPerson, active: active, lit: active && model.isWriting)
                .contentShape(.rect)
                .opacity(dimmed ? 0.4 : 1)
        }
        .buttonStyle(BarPressStyle())
        .disabled(dimmed)
    }

    private var askField: some View {
        Button {
            UIDevice.current.playInputClick()
            actions.ask()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(style.text))
                Text(KeyboardText.string("Ask for any change…"))
                    .font(BrandFont.font(size: 15))
                    .foregroundStyle(Color(style.secondary))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(style.background))
                    .frame(width: 32, height: 32)
                    .background(Color(style.text), in: .circle)
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(height: 44)
            .background(Color(style.key), in: .capsule)
            .overlay {
                Capsule().strokeBorder(Color(style.outline), lineWidth: 0.5)
            }
            .contentShape(.capsule)
            .opacity(model.isWriting ? 0.4 : 1)
        }
        .buttonStyle(BarPressStyle())
        .disabled(model.isWriting)
    }

    private var settings: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)

            HStack(spacing: 2) {
                ForEach(KeyboardLanguage.allCases) { language in
                    let selected = model.options.language == language
                    Button {
                        actions.setLanguage(language)
                    } label: {
                        Text(code(language))
                            .font(BrandFont.font(size: 13, weight: .medium))
                            .foregroundStyle(Color(selected ? style.text : style.secondary))
                            .frame(minWidth: 38)
                            .frame(height: 26)
                            .background {
                                if selected {
                                    Capsule().fill(Color(style.key))
                                }
                            }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(BarPressStyle())
                    .accessibilityLabel(language.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(2)
            .background(Color(style.key).opacity(0.45), in: .capsule)
        }
        .frame(height: 30)
    }

    private func code(_ language: KeyboardLanguage) -> String {
        switch language {
        case .automatic: KeyboardText.string("Auto")
        case .english: "EN"
        case .spanish: "ES"
        }
    }

    private func pill(_ title: String, symbol: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            UIDevice.current.playInputClick()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(BrandFont.font(size: 14, weight: .medium))
            }
            .foregroundStyle(filled ? .white : Color(style.text))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(filled ? Color(KeyStyle.blue) : Color(style.key), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(BarPressStyle())
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
