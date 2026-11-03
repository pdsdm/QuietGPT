import SwiftUI

struct HushPanel: View {
    let model: KeyboardModel
    let actions: BarActions

    @Environment(\.colorScheme) private var scheme

    private var style: KeyStyle { .current(scheme) }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(spacing: 10) {
            header
            tiles
            Spacer(minLength: 0)
            settings
        }
        .padding(.horizontal, 8)
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
                    .font(.system(size: 11))
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
            pill("ABC", symbol: "keyboard", action: actions.close)
        }
        .frame(minHeight: 36)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var status: String {
        if let hint = model.hint { return hint }
        if model.isWriting { return KeyboardText.string("rewriting…") }
        return KeyboardText.string("on this iPhone")
    }

    private var tiles: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(model.styles) { value in
                    tile(value.title, active: model.active == value.id) {
                        actions.rewrite(value)
                    }
                }
                if model.showsAsk {
                    tile(KeyboardText.string("Ask"), symbol: "text.bubble", active: false, action: actions.ask)
                }
            }
        }
        .contentMargins(.vertical, 2, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 44 * 2 + 6 + 4)
    }

    private func tile(_ title: String, symbol: String? = nil, active: Bool, action: @escaping () -> Void) -> some View {
        let dimmed = model.isWriting && !active
        return Button {
            UIDevice.current.playInputClick()
            action()
        } label: {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if active && model.isWriting {
                    Caret(color: Color(style.accent), height: 15)
                }
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color(style.text))
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color(style.key), in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(active ? Color(style.accent) : Color(style.outline), lineWidth: active ? 1.5 : 0.5)
            }
            .contentShape(.rect)
            .opacity(dimmed ? 0.4 : 1)
        }
        .buttonStyle(BarPressStyle())
        .disabled(dimmed)
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
                            .font(.system(size: 13, weight: .medium))
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

            toggle("Aa", isOn: model.options.autoCapitalize, label: "Auto capitals", action: actions.setAutoCapitalize)
            toggle("␣ .", isOn: model.options.periodShortcut, label: "Double space adds a period", action: actions.setPeriodShortcut)
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

    private func toggle(_ title: String, isOn: Bool, label: String, action: @escaping (Bool) -> Void) -> some View {
        Button {
            action(!isOn)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(isOn ? style.accent : style.secondary))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Color(style.key).opacity(isOn ? 1 : 0.45), in: .capsule)
                .overlay {
                    Capsule().strokeBorder(isOn ? Color(style.accent).opacity(0.6) : .clear, lineWidth: 1)
                }
                .contentShape(.capsule)
        }
        .buttonStyle(BarPressStyle())
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
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
                    .font(.system(size: 14, weight: .medium))
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
