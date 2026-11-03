import SwiftUI

struct QuietGPTPanel: View {
    let model: KeyboardModel
    let actions: BarActions

    @Environment(\.colorScheme) private var scheme

    private var style: KeyStyle { .current(scheme) }

    var body: some View {
        VStack(spacing: 10) {
            header
                .padding(.horizontal, 12)
            rail
            if model.showsAsk {
                askField
                    .padding(.horizontal, 12)
            }
            Spacer(minLength: 0)
            settings
                .padding(.horizontal, 12)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            Button {
                UIDevice.current.playInputClick()
                actions.close()
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(style.text))
                    .frame(width: 44, height: 30)
                    .background(Color(style.key), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(BarPressStyle())
            .accessibilityLabel(KeyboardText.string("Back to letters"))
        }
        .frame(minHeight: 36)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var status: String {
        if let hint = model.hint { return hint }
        if model.isWriting { return KeyboardText.string("rewriting…") }
        return KeyboardText.string("on this iPhone")
    }

    private var rail: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
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
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0.82), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
        }
        .frame(height: 86)
    }

    private func tile(_ value: RewriteStyle, active: Bool, action: @escaping () -> Void) -> some View {
        let dimmed = model.isWriting && !active
        let lit = active && model.isWriting
        return Button {
            UIDevice.current.playInputClick()
            action()
        } label: {
            VStack(spacing: 8) {
                badge(for: value, lit: lit)
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
            .contentShape(.rect)
            .opacity(dimmed ? 0.4 : 1)
        }
        .buttonStyle(BarPressStyle())
        .disabled(dimmed)
    }

    private func badge(for value: RewriteStyle, lit: Bool) -> some View {
        let ink = Color(lit ? style.background : style.text)
        return ZStack {
            Circle()
                .fill(lit ? Color(style.text) : Color(style.lit).opacity(0.45))
            if let code = Self.codes[value.id] {
                Text(code)
                    .font(BrandFont.font(size: 12, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(ink)
            } else {
                Image(systemName: Self.symbols[value.id] ?? "pencil")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ink)
            }
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }

    private static let symbols: [RewriteStyle.ID: String] = {
        let names = ["heart", "arrow.down.right.and.arrow.up.left", "arrow.up.left.and.arrow.down.right", "briefcase", "checkmark"]
        return Dictionary(uniqueKeysWithValues: zip(RewriteStyle.builtIn.prefix(5).map(\.id), names))
    }()

    private static let codes: [RewriteStyle.ID: String] = {
        Dictionary(uniqueKeysWithValues: zip(RewriteStyle.builtIn.dropFirst(5).map(\.id), ["EN", "ES"]))
    }()

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

            Spacer(minLength: 0)
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
