import SwiftUI
import UIKit

struct KeyboardView: View {
    static let barHeight: CGFloat = 88
    static let rowHeight: CGFloat = 56
    static let topPadding: CGFloat = 2.5
    static let bottomPadding: CGFloat = 0
    static let height: CGFloat = barHeight + topPadding + rowHeight * 4 + bottomPadding

    let model: KeyboardModel
    let actions: KeyboardActions

    @Environment(\.colorScheme) private var scheme
    @State private var repeating: Task<Void, Never>?

    private var style: KeyStyle { .current(scheme) }

    private static let variants: [String: [String]] = [
        "a": ["à", "á", "â", "ä", "æ", "ã", "å", "ā", "ª"],
        "e": ["è", "é", "ê", "ë", "ē", "ė", "ę"],
        "i": ["î", "ï", "í", "ī", "į", "ì"],
        "o": ["ô", "ö", "ò", "ó", "œ", "ø", "ō", "õ", "º"],
        "u": ["û", "ü", "ù", "ú", "ū"],
        "n": ["ñ", "ń"],
        "c": ["ç", "ć", "č"],
        "s": ["ß", "ś", "š"],
        "l": ["ł", "l·l"],
        "y": ["ÿ"],
        "z": ["ž", "ź", "ż"],
        "?": ["¿"],
        "!": ["¡"],
        ".": ["…"],
        "-": ["–", "—", "•"],
        "'": ["’", "‘", "`"],
        "\"": ["“", "”", "„", "«", "»"],
        "$": ["€", "£", "¥", "₩", "₽"],
        "€": ["$", "£", "¥", "₩", "₽"],
        "0": ["°"],
        "&": ["§"],
        "%": ["‰"]
    ]

    private static let emojis = Array(
        "😀😃😄😁😆🥹😅😂🤣🥲☺️😊😇🙂🙃😉😌😍🥰😘😗😙😚😋😛😝😜🤪🤨🧐🤓😎🥸🤩🥳🙂‍↕️😏😒🙂‍↔️😞😔😟😕🙁☹️😣😖😫😩🥺😢😭😮‍💨😤😠😡🤬🤯😳🥵🥶😱😨😰😥😓🫣🤗🫡🤔🫢🤭🤫🤥😶😐😑😬🫨🙄😯😦😧😮😲🥱😴🤤😪😵🤐🥴🤢🤮🤧😷🤒🤕🤑🤠😈👿👹👺🤡💩👻💀👽🤖🎃😺😸😹😻😼😽🙀😿😾👋🤚🖐✋🖖👌🤌🤏✌️🤞🫰🤟🤘🤙👈👉👆👇☝️👍👎✊👊🤛🤜👏🙌🫶👐🤲🤝🙏💪❤️🧡💛💚💙💜🖤🤍🤎💔❣️💕💞💓💗💖💘💝🔥✨🎉🎂🎁⭐️🌟💫☀️🌙⚡️🌈☕️🍕🍔🍟🍣🍷🍺🥂⚽️🏀🎾🚗✈️🏖🏠💼📱💻📷🎵🎶✅❌⚠️💯❓❗️👀💬"
    ).map(String.init)

    var body: some View {
        VStack(spacing: 0) {
            HushBar(model: model, actions: actions)
                .frame(height: Self.barHeight)
            GeometryReader { geometry in
                let margin: CGFloat = 1
                let unit = (geometry.size.width - margin * 2) / 10
                let bounds = margin...(geometry.size.width - margin)
                VStack(spacing: 0) {
                    switch model.layer {
                    case .letters:
                        row { characters("qwertyuiop", unit: unit, bounds: bounds, edges: true) }
                        if model.isSpanish {
                            row { characters("asdfghjklñ", unit: unit, bounds: bounds, edges: true) }
                        } else {
                            row { characters("asdfghjkl", unit: unit, bounds: bounds, outer: unit / 2) }
                        }
                        row {
                            shiftKey(unit: unit)
                            characters("zxcvbnm", unit: unit, bounds: bounds)
                            deleteKey(unit: unit)
                        }
                    case .numbers:
                        row { characters("1234567890", unit: unit, bounds: bounds, edges: true) }
                        row { characters(["-", "/", ":", ";", "(", ")", model.isSpanish ? "€" : "$", "&", "@", "\""], unit: unit, bounds: bounds, edges: true) }
                        punctuationRow(switchTitle: "#+=", unit: unit, bounds: bounds)
                    case .symbols:
                        row { characters(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="], unit: unit, bounds: bounds, edges: true) }
                        row { characters(["_", "\\", "|", "~", "<", ">", model.isSpanish ? "$" : "€", "£", "¥", "•"], unit: unit, bounds: bounds, edges: true) }
                        punctuationRow(switchTitle: "123", unit: unit, bounds: bounds)
                    case .emoji:
                        emojiGrid
                            .frame(height: Self.rowHeight * 3)
                    }
                    bottomRow(unit: unit)
                }
                .padding(.horizontal, margin)
                .coordinateSpace(.named(CharacterKey.space))
            }
            .padding(.top, Self.topPadding)
            .frame(height: Self.topPadding + Self.rowHeight * 4)
            .animation(.easeOut(duration: 0.15), value: model.isTrackpad)
        }
        .padding(.bottom, Self.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func row(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 0) {
            content()
        }
        .frame(height: Self.rowHeight)
    }

    private func characters(_ text: String, unit: CGFloat, bounds: ClosedRange<CGFloat>, outer: CGFloat = 0, edges: Bool = false) -> some View {
        characters(text.map(String.init), unit: unit, bounds: bounds, outer: outer, edges: edges)
    }

    private func characters(_ keys: [String], unit: CGFloat, bounds: ClosedRange<CGFloat>, width: CGFloat = 1, outer: CGFloat = 0, edges: Bool = false) -> some View {
        ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
            let first = index == 0
            let last = index == keys.count - 1
            CharacterKey(
                character: key,
                uppercase: model.layer == .letters && model.shift != .off,
                variants: Self.variants[key] ?? [],
                opensLeft: index >= keys.count / 2,
                edge: edges && first ? .leading : edges && last ? .trailing : .none,
                insets: .key(leading: first ? outer : 0, trailing: last ? outer : 0),
                bounds: bounds,
                isBlank: model.isTrackpad,
                onInsert: actions.insert
            )
            .frame(width: unit * width + (first ? outer : 0) + (last ? outer : 0), height: Self.rowHeight)
        }
    }

    private func punctuationRow(switchTitle: String, unit: CGFloat, bounds: ClosedRange<CGFloat>) -> some View {
        row {
            FunctionKey(insets: .key(trailing: unit * 0.2), isBlank: model.isTrackpad, onPress: actions.shift) { _ in
                Text(switchTitle).font(.system(size: 14))
            }
            .frame(width: unit * 1.5)
            characters([".", ",", "?", "!", "'"], unit: unit, bounds: bounds, width: 1.4)
            deleteKey(unit: unit)
        }
    }

    private var emojiGrid: some View {
        ScrollView(.horizontal) {
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(42), spacing: 0), count: 4), spacing: 0) {
                ForEach(Array(Self.emojis.enumerated()), id: \.offset) { _, emoji in
                    Text(emoji)
                        .font(.system(size: 32))
                        .frame(width: 44, height: 42)
                        .contentShape(.rect)
                        .onTapGesture {
                            UIDevice.current.playInputClick()
                            actions.insert(emoji)
                        }
                }
            }
            .padding(.horizontal, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func icon(_ name: String, size: CGFloat = 19) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .regular))
    }

    private func shiftKey(unit: CGFloat) -> some View {
        FunctionKey(insets: .key(trailing: unit * 0.2), isBlank: model.isTrackpad, onPress: actions.shift) { _ in
            icon(shiftSymbol)
        }
        .frame(width: unit * 1.5)
        .accessibilityLabel(model.shift == .locked ? "Caps lock" : "Shift")
    }

    private var shiftSymbol: String {
        switch model.shift {
        case .off: "shift"
        case .once: "shift.fill"
        case .locked: "capslock.fill"
        }
    }

    private func deleteKey(unit: CGFloat) -> some View {
        FunctionKey(insets: .key(leading: unit * 0.2), isBlank: model.isTrackpad, onPress: startDelete, onRelease: stopDelete) { pressed in
            icon(pressed ? "delete.left.fill" : "delete.left")
        }
        .frame(width: unit * 1.5)
        .accessibilityLabel("Delete")
    }

    private func bottomRow(unit: CGFloat) -> some View {
        row {
            FunctionKey(isBlank: model.isTrackpad, onRelease: { actions.show(model.layer == .letters ? .numbers : .letters) }) { _ in
                Text(model.layer == .letters ? "123" : "ABC").font(.system(size: 18.5))
            }
            .frame(width: unit * 1.25)
            if model.showsGlobe {
                FunctionKey(isBlank: model.isTrackpad, onRelease: actions.nextKeyboard) { _ in
                    icon("globe")
                }
                .frame(width: unit * 1.25)
                .accessibilityLabel("Next keyboard")
            } else {
                FunctionKey(isBlank: model.isTrackpad, onRelease: { actions.show(model.layer == .emoji ? .letters : .emoji) }) { _ in
                    icon(model.layer == .emoji ? "keyboard" : "face.smiling", size: 19)
                }
                .frame(width: unit * 1.25)
                .accessibilityLabel("Emoji")
            }
            SpaceKey(
                tag: model.isSpanish ? "ES" : "EN",
                title: model.spaceTitle,
                onSpace: actions.space,
                onTrackpad: actions.trackpad,
                onMove: actions.moveCursor
            )
            .frame(width: unit * 5)
            if model.layer == .emoji {
                deleteKey(unit: unit)
                    .frame(width: unit * 2.5)
            } else {
                FunctionKey(isAction: model.returnIsAction || model.isAsking, isBlank: model.isTrackpad, onRelease: actions.newline) { _ in
                    if model.isAsking {
                        Text(model.goTitle).font(.system(size: 17))
                    } else if model.returnIsAction {
                        Text(model.returnTitle).font(.system(size: 17))
                    } else {
                        icon("return.left")
                    }
                }
                .frame(width: unit * 2.5)
                .accessibilityLabel(model.isAsking ? model.goTitle : model.returnTitle)
            }
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
    @State private var pressedTone: RewriteTone?

    private var style: KeyStyle { .current(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("hush")
                        .font(.system(size: 20, weight: .light))
                        .tracking(-0.8)
                        .foregroundStyle(style.text)
                    caret(height: 14, blinks: model.isWriting)
                }
                Spacer(minLength: 4)
                Text(model.isAsking ? "type how to rewrite it" : model.hint)
                    .font(.system(size: 13))
                    .foregroundStyle(style.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                roundButton(symbol: "text.bubble", active: model.isAsking, action: actions.ask)
                    .accessibilityLabel(model.isAsking ? "Cancel instruction" : "Tell Hush how to rewrite")
                if model.canUndo {
                    roundButton(symbol: "arrow.uturn.backward", active: false, action: actions.undo)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                        .accessibilityLabel("Undo rewrite")
                }
            }
            .frame(height: 32)

            ZStack {
                if model.isAsking {
                    askRow
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    chips
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(height: 32)
            .clipped()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .animation(.snappy, value: model.isAsking)
        .animation(.snappy, value: model.hint)
        .animation(.snappy, value: model.canUndo)
        .animation(.snappy, value: model.tone)
        .animation(.snappy, value: model.pinned)
        .animation(.snappy, value: model.isWriting)
    }

    @ViewBuilder
    private func caret(height: CGFloat, blinks: Bool, color: Color? = nil) -> some View {
        let shape = Capsule().fill(color ?? style.accent).frame(width: 2, height: height)
        if blinks {
            shape.phaseAnimator([1.0, 0.15]) { content, phase in
                content.opacity(phase)
            } animation: { _ in
                .easeInOut(duration: 0.45)
            }
        } else {
            shape
        }
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(model.tones) { tone in
                    let selected = tone == model.tone
                    HStack(spacing: 4) {
                        if tone == model.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10))
                                .transition(.scale.combined(with: .opacity))
                        }
                        Text(tone.title).font(.system(size: 14))
                        if selected && model.isWriting {
                            caret(height: 12, blinks: true, color: style.onSelected)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .foregroundStyle(selected ? style.onSelected : style.text)
                    .background(selected ? style.selected : style.key, in: .capsule)
                    .opacity(model.isWriting && !selected ? 0.5 : 1)
                    .scaleEffect(pressedTone == tone ? 0.94 : 1)
                    .animation(.snappy(duration: 0.2), value: pressedTone)
                    .contentShape(.capsule)
                    .onTapGesture {
                        guard !model.isWriting else { return }
                        UIDevice.current.playInputClick()
                        actions.rewrite(tone)
                    }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        actions.pin(tone)
                    } onPressingChanged: { pressing in
                        pressedTone = pressing ? tone : nil
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
            HStack(spacing: 1) {
                Text(model.instruction.isEmpty ? "make it warmer and a bit shorter" : model.instruction)
                    .font(.system(size: 15))
                    .foregroundStyle(model.instruction.isEmpty ? style.secondary : style.text)
                    .lineLimit(1)
                    .truncationMode(.head)
                if !model.instruction.isEmpty {
                    caret(height: 16, blinks: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: actions.submitAsk) {
                Text(model.goTitle)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .foregroundStyle(Color.white)
                    .background(KeyStyle.blue, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(model.instruction.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(style.key, in: .capsule)
    }

    private func roundButton(symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 32, height: 32)
                .foregroundStyle(active ? Color.white : style.text)
                .background(active ? style.accent : style.key, in: .circle)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
}
