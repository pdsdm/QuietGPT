import SwiftUI
import UIKit

struct KeyboardView: View {
    static let barHeight: CGFloat = 88
    static let rowHeight: CGFloat = 54
    static let height: CGFloat = barHeight + rowHeight * 4 + 2

    let model: KeyboardModel
    let actions: KeyboardActions

    @Environment(\.colorScheme) private var scheme
    @State private var repeating: Task<Void, Never>?

    private var style: KeyStyle { .current(scheme) }

    private static let variants: [String: [String]] = [
        "a": ["á", "à", "ä", "â", "ã", "å", "æ", "ª"],
        "e": ["é", "è", "ë", "ê", "ē", "€"],
        "i": ["í", "ì", "ï", "î"],
        "o": ["ó", "ò", "ö", "ô", "õ", "ø", "œ", "º"],
        "u": ["ú", "ü", "ù", "û"],
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
        "\"": ["“", "”", "«", "»", "„"],
        "€": ["$", "£", "¥", "₩"],
        "0": ["°"],
        "&": ["§"],
        "%": ["‰"]
    ]

    var body: some View {
        VStack(spacing: 0) {
            HushBar(model: model, actions: actions)
                .frame(height: Self.barHeight)
            GeometryReader { geometry in
                let unit = geometry.size.width / 10
                VStack(spacing: 0) {
                    switch model.layer {
                    case .letters:
                        row { characters("qwertyuiop", unit: unit, edges: true) }
                        if model.isSpanish {
                            row { characters("asdfghjklñ", unit: unit, edges: true) }
                        } else {
                            row { characters("asdfghjkl", unit: unit, outer: unit / 2) }
                        }
                        row {
                            shiftKey(unit: unit)
                            characters("zxcvbnm", unit: unit)
                            deleteKey(unit: unit)
                        }
                    case .numbers:
                        row { characters("1234567890", unit: unit, edges: true) }
                        row { characters(["-", "/", ":", ";", "(", ")", "€", "&", "@", "\""], unit: unit, edges: true) }
                        punctuationRow(switchTitle: "#+=", unit: unit)
                    case .symbols:
                        row { characters(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="], unit: unit, edges: true) }
                        row { characters(["_", "\\", "|", "~", "<", ">", "$", "£", "¥", "•"], unit: unit, edges: true) }
                        punctuationRow(switchTitle: "123", unit: unit)
                    }
                    bottomRow(unit: unit)
                }
            }
            .frame(height: Self.rowHeight * 4)
            .animation(.easeOut(duration: 0.15), value: model.isTrackpad)
        }
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func row(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 0) {
            content()
        }
        .frame(height: Self.rowHeight)
    }

    private func characters(_ text: String, unit: CGFloat, outer: CGFloat = 0, edges: Bool = false) -> some View {
        characters(text.map(String.init), unit: unit, outer: outer, edges: edges)
    }

    private func characters(_ keys: [String], unit: CGFloat, width: CGFloat = 1, outer: CGFloat = 0, edges: Bool = false) -> some View {
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
                isBlank: model.isTrackpad,
                onInsert: actions.insert
            )
            .frame(width: unit * width + (first ? outer : 0) + (last ? outer : 0), height: Self.rowHeight)
        }
    }

    private func punctuationRow(switchTitle: String, unit: CGFloat) -> some View {
        row {
            FunctionKey(insets: .key(trailing: unit / 4), onPress: actions.shift) {
                label(switchTitle)
            }
            .frame(width: unit * 1.5)
            characters([".", ",", "?", "!", "'"], unit: unit, width: 1.4)
            deleteKey(unit: unit)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16))
            .opacity(model.isTrackpad ? 0 : 1)
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 18))
            .opacity(model.isTrackpad ? 0 : 1)
    }

    private func shiftKey(unit: CGFloat) -> some View {
        FunctionKey(isLight: model.shift != .off, insets: .key(trailing: unit / 4), onPress: actions.shift) {
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
        FunctionKey(insets: .key(leading: unit / 4), onPress: startDelete, onRelease: stopDelete) {
            icon("delete.left")
        }
        .frame(width: unit * 1.5)
        .accessibilityLabel("Delete")
    }

    private func bottomRow(unit: CGFloat) -> some View {
        row {
            FunctionKey(onRelease: { actions.show(model.layer == .letters ? .numbers : .letters) }) {
                label(model.layer == .letters ? "123" : "ABC")
            }
            .frame(width: unit * (model.showsGlobe ? 1.25 : 2.5))
            if model.showsGlobe {
                FunctionKey(onRelease: actions.nextKeyboard) {
                    icon("globe")
                }
                .frame(width: unit * 1.25)
                .accessibilityLabel("Next keyboard")
            }
            SpaceKey(
                title: model.spaceTitle,
                onSpace: actions.space,
                onTrackpad: actions.trackpad,
                onMove: actions.moveCursor
            )
            .frame(width: unit * 5)
            FunctionKey(isAction: model.returnIsAction || model.isAsking, onRelease: actions.newline) {
                label(model.isAsking ? model.goTitle : model.returnTitle)
            }
            .frame(width: unit * 2.5)
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
        .overlay(alignment: .bottom) {
            Rectangle().fill(style.shadow.opacity(0.35)).frame(height: 1)
        }
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
                    .shadow(color: selected ? .clear : style.shadow, radius: 0, x: 0, y: 1)
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
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
}
