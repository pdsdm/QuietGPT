import SwiftUI

struct KeyboardView: View {
    static let height: CGFloat = 306

    let model: KeyboardModel
    let actions: KeyboardActions

    @Environment(\.colorScheme) private var scheme
    @State private var repeating: Task<Void, Never>?

    private var style: KeyStyle { .current(scheme) }

    private static let variants: [String: [String]] = [
        "a": ["á", "à", "ä", "â", "ã", "å", "æ"],
        "e": ["é", "è", "ë", "ê", "€"],
        "i": ["í", "ì", "ï", "î"],
        "o": ["ó", "ò", "ö", "ô", "õ", "ø", "œ"],
        "u": ["ú", "ù", "ü", "û"],
        "n": ["ñ", "ń"],
        "c": ["ç", "ć"],
        "s": ["ß", "ś"],
        "?": ["¿"],
        "!": ["¡"],
        "-": ["–", "—", "•"],
        "'": ["’", "‘", "`"],
        "\"": ["“", "”", "«", "»"]
    ]

    var body: some View {
        VStack(spacing: 9) {
            HushBar(model: model, actions: actions)
            VStack(spacing: 11) {
                switch model.layer {
                case .letters:
                    characterRow("qwertyuiop")
                    characterRow("asdfghjkl").padding(.horizontal, 19)
                    HStack(spacing: 6) {
                        shiftKey.frame(width: 42).padding(.trailing, 8)
                        characters("zxcvbnm")
                        deleteKey.frame(width: 42).padding(.leading, 8)
                    }
                case .numbers:
                    characterRow("1234567890")
                    characterRow(["-", "/", ":", ";", "(", ")", "€", "&", "@", "\""])
                    punctuationRow(switchTitle: "#+=")
                case .symbols:
                    characterRow(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="])
                    characterRow(["_", "\\", "|", "~", "<", ">", "$", "£", "¥", "•"])
                    punctuationRow(switchTitle: "123")
                }
                bottomRow
            }
            .frame(height: 201)
            .padding(.horizontal, 3)
        }
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func characterRow(_ text: String) -> some View {
        characterRow(text.map(String.init))
    }

    private func characterRow(_ keys: [String]) -> some View {
        HStack(spacing: 6) {
            characters(keys)
        }
    }

    private func characters(_ text: String) -> some View {
        characters(text.map(String.init))
    }

    private func characters(_ keys: [String]) -> some View {
        ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
            CharacterKey(
                character: key,
                uppercase: model.layer == .letters && model.shift != .off,
                variants: Self.variants[key] ?? [],
                opensLeft: index >= keys.count / 2,
                onInsert: actions.insert
            )
        }
    }

    private func punctuationRow(switchTitle: String) -> some View {
        HStack(spacing: 6) {
            FunctionKey(onPress: actions.shift) {
                Text(switchTitle).font(.system(size: 16))
            }
            .frame(width: 54)
            .padding(.trailing, 6)
            characters([".", ",", "?", "!", "'"])
            deleteKey.frame(width: 54).padding(.leading, 6)
        }
    }

    private var shiftKey: some View {
        FunctionKey(isLight: model.shift != .off, onPress: actions.shift) {
            Image(systemName: shiftSymbol).font(.system(size: 18))
        }
        .accessibilityLabel(model.shift == .locked ? "Caps lock" : "Shift")
    }

    private var shiftSymbol: String {
        switch model.shift {
        case .off: "shift"
        case .once: "shift.fill"
        case .locked: "capslock.fill"
        }
    }

    private var deleteKey: some View {
        FunctionKey(onPress: startDelete, onRelease: stopDelete) {
            Image(systemName: "delete.left").font(.system(size: 18))
        }
        .accessibilityLabel("Delete")
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            FunctionKey(onRelease: { actions.show(model.layer == .letters ? .numbers : .letters) }) {
                Text(model.layer == .letters ? "123" : "ABC").font(.system(size: 16))
            }
            .frame(width: model.showsGlobe ? 44 : 92)
            if model.showsGlobe {
                FunctionKey(onRelease: actions.nextKeyboard) {
                    Image(systemName: "globe").font(.system(size: 18))
                }
                .frame(width: 44)
                .accessibilityLabel("Next keyboard")
            }
            FunctionKey(isLight: true, onRelease: actions.space) {
                Text("space")
                    .font(.system(size: 15))
                    .foregroundStyle(style.secondary)
            }
            FunctionKey(isAction: model.returnIsAction || model.isAsking, onRelease: actions.newline) {
                Text(model.isAsking ? "go" : model.returnTitle).font(.system(size: 16))
            }
            .frame(width: 92)
        }
    }

    private func startDelete() {
        actions.deleteBackward()
        repeating?.cancel()
        repeating = Task {
            try? await Task.sleep(for: .milliseconds(450))
            var count = 0
            while !Task.isCancelled {
                if count < 18 {
                    actions.deleteBackward()
                    try? await Task.sleep(for: .milliseconds(80))
                } else {
                    actions.deleteWord()
                    try? await Task.sleep(for: .milliseconds(220))
                }
                count += 1
            }
        }
    }

    private func stopDelete() {
        repeating?.cancel()
        repeating = nil
    }
}

struct HushBar: View {
    let model: KeyboardModel
    let actions: KeyboardActions

    @Environment(\.colorScheme) private var scheme

    private var style: KeyStyle { .current(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("hush")
                        .font(.system(size: 20, weight: .light))
                        .tracking(-0.8)
                        .foregroundStyle(style.text)
                    Capsule()
                        .fill(style.accent)
                        .frame(width: 2, height: 14)
                        .opacity(model.isWriting ? 0.35 : 1)
                }
                Spacer(minLength: 4)
                Text(model.isAsking ? "type how to rewrite it" : model.hint)
                    .font(.system(size: 13))
                    .foregroundStyle(style.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                roundButton(symbol: "text.bubble", active: model.isAsking, action: actions.ask)
                    .accessibilityLabel(model.isAsking ? "Cancel instruction" : "Tell Hush how to rewrite")
                roundButton(symbol: "arrow.uturn.backward", active: false, action: actions.undo)
                    .disabled(!model.canUndo)
                    .opacity(model.canUndo ? 1 : 0.4)
                    .accessibilityLabel("Undo rewrite")
            }
            .frame(height: 32)

            Group {
                if model.isAsking {
                    askRow
                } else {
                    chips
                }
            }
            .frame(height: 32)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(style.shadow.opacity(0.35)).frame(height: 1)
        }
        .animation(.snappy, value: model.isAsking)
        .animation(.snappy, value: model.hint)
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(model.tones) { tone in
                    let selected = tone == model.tone
                    HStack(spacing: 4) {
                        if tone == model.pinned {
                            Image(systemName: "pin.fill").font(.system(size: 10))
                        }
                        Text(tone.title).font(.system(size: 14))
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .foregroundStyle(selected ? style.onSelected : style.text)
                    .background(selected ? style.selected : style.key, in: .capsule)
                    .shadow(color: selected ? .clear : style.shadow, radius: 0, x: 0, y: 1)
                    .opacity(model.isWriting && !selected ? 0.5 : 1)
                    .contentShape(.capsule)
                    .onTapGesture {
                        guard !model.isWriting else { return }
                        actions.rewrite(tone)
                    }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        actions.pin(tone)
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: "Pin") { actions.pin(tone) }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }

    private var askRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.cursor")
                .font(.system(size: 14))
                .foregroundStyle(style.accent)
            Text(model.instruction.isEmpty ? "make it warmer and a bit shorter" : model.instruction)
                .font(.system(size: 15))
                .foregroundStyle(model.instruction.isEmpty ? style.secondary : style.text)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: actions.submitAsk) {
                Text("go")
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .foregroundStyle(Color.white)
                    .background(Color.accentColor, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(model.instruction.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(style.key, in: .capsule)
        .shadow(color: style.shadow, radius: 0, x: 0, y: 1)
    }

    private func roundButton(symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 32, height: 32)
                .foregroundStyle(active ? Color.white : style.text)
                .background(active ? style.accent : style.key, in: .circle)
                .shadow(color: active ? .clear : style.shadow, radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}
