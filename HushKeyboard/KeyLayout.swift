import UIKit

enum KeyEdge {
    case none
    case leading
    case trailing
}

enum KeyKind: Equatable {
    case character(String)
    case shift
    case delete
    case layer(KeyboardModel.Layer)
    case emoji(KeyboardModel.Layer)
    case symbols
    case globe
    case space
    case enter
    case hush
}

struct KeySpec {
    var id: String
    var kind: KeyKind
    var cell = CGRect.zero
    var face = CGRect.zero
    var title: String?
    var fontSize: CGFloat = 22
    var symbol: String?
    var symbolSize: CGFloat = 19
    var tag: String?
    var isAction = false
    var edge = KeyEdge.none
    var variants: [String] = []
    var opensLeft = false
    var label: String

    var character: String? {
        if case .character(let value) = kind { return value }
        return nil
    }
}

enum KeyLayout {
    static let rowHeight: CGFloat = 56
    static let topPadding: CGFloat = 2.5
    static let height = topPadding + rowHeight * 4
    static let bottomPadding: CGFloat = -0.33
    static let margin: CGFloat = 1
    static let insetX: CGFloat = 3
    static let insetY: CGFloat = 5.5

    private struct Item {
        var spec: KeySpec
        var units: CGFloat
        var lead: CGFloat = 0
        var trail: CGFloat = 0
    }

    static let variants: [String: [String]] = [
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

    static func height(rowHeight: CGFloat) -> CGFloat {
        topPadding + rowHeight * 4
    }

    static func build(_ state: KeyState, width: CGFloat, rowHeight: CGFloat = rowHeight) -> [KeySpec] {
        guard width > 0 else { return [] }
        let height = height(rowHeight: rowHeight)
        let insetY = insetY * rowHeight / Self.rowHeight
        let unit = (width - margin * 2) / 10
        let uppercase = state.layer == .letters && state.shift != .off
        var rows: [[Item]] = []

        func characters(_ keys: [String], units: CGFloat = 1, outer: CGFloat = 0, edges: Bool = false) -> [Item] {
            keys.enumerated().map { index, key in
                let first = index == 0
                let last = index == keys.count - 1
                let shown = uppercase ? key.uppercased() : key
                let lower = !uppercase && key.lowercased() == key && key.uppercased() != key
                let spec = KeySpec(
                    id: "c:" + key,
                    kind: .character(key),
                    title: shown,
                    fontSize: lower ? 24 : 22,
                    edge: edges && first ? .leading : edges && last ? .trailing : .none,
                    variants: variants[key] ?? [],
                    opensLeft: index >= keys.count / 2,
                    label: shown
                )
                return Item(
                    spec: spec,
                    units: units + (first ? outer : 0) + (last ? outer : 0),
                    lead: first ? outer * unit : 0,
                    trail: last ? outer * unit : 0
                )
            }
        }

        func letters(_ text: String) -> [String] { text.map(String.init) }

        let delete = Item(spec: KeySpec(id: "delete", kind: .delete, symbol: "delete.left", label: "Delete"), units: 1.5, lead: unit * 0.2)

        switch state.layer {
        case .letters:
            let shiftSymbol = switch state.shift {
            case .off: "shift"
            case .once: "shift.fill"
            case .locked: "capslock.fill"
            }
            rows.append(characters(letters("qwertyuiop"), edges: true))
            rows.append(state.isSpanish ? characters(letters("asdfghjklñ"), edges: true) : characters(letters("asdfghjkl"), outer: 0.5))
            rows.append(
                [Item(spec: KeySpec(id: "shift", kind: .shift, symbol: shiftSymbol, label: state.shift == .locked ? "Caps lock" : "Shift"), units: 1.5, trail: unit * 0.2)]
                + characters(letters("zxcvbnm"))
                + [delete]
            )
        case .numbers, .symbols:
            let numbers = state.layer == .numbers
            if numbers {
                rows.append(characters(letters("1234567890"), edges: true))
                rows.append(characters(["-", "/", ":", ";", "(", ")", state.isSpanish ? "€" : "$", "&", "@", "\""], edges: true))
            } else {
                rows.append(characters(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="], edges: true))
                rows.append(characters(["_", "\\", "|", "~", "<", ">", state.isSpanish ? "$" : "€", "£", "¥", "•"], edges: true))
            }
            let title = numbers ? "#+=" : "123"
            rows.append(
                [Item(spec: KeySpec(id: "symbols", kind: .symbols, title: title, fontSize: 16, label: numbers ? "More symbols" : "Numbers"), units: 1.5, trail: unit * 0.2)]
                + characters([".", ",", "?", "!", "'"], units: 1.4)
                + [delete]
            )
        case .emoji:
            break
        }

        var bottom: [Item] = []
        let toLetters = state.layer != .letters
        bottom.append(Item(spec: KeySpec(id: "switch", kind: .layer(toLetters ? .letters : .numbers), title: toLetters ? "ABC" : "123", fontSize: 18.5, label: toLetters ? "Letters" : "Numbers"), units: 1.25))
        if state.showsGlobe {
            bottom.append(Item(spec: KeySpec(id: "globe", kind: .globe, symbol: "globe", label: "Next keyboard"), units: 1.0))
        } else {
            let inEmoji = state.layer == .emoji
            bottom.append(Item(spec: KeySpec(id: "emoji", kind: .emoji(inEmoji ? .letters : .emoji), symbol: inEmoji ? "keyboard" : "face.smiling.inverse", symbolSize: 20, label: inEmoji ? "Letters" : "Emoji"), units: 1.0))
        }
        bottom.append(Item(spec: KeySpec(id: "hush", kind: .hush, label: "QuietGPT"), units: 1.0))
        bottom.append(Item(spec: KeySpec(id: "space", kind: .space, tag: state.isSpanish ? "ES" : "EN", label: KeyboardText.string("space")), units: 4.5))
        if state.layer == .emoji {
            var wide = delete
            wide.units = 2.25
            wide.lead = 0
            bottom.append(wide)
        } else {
            bottom.append(Item(
                spec: KeySpec(
                    id: "return",
                    kind: .enter,
                    title: state.returnSymbol == nil ? state.returnTitle : nil,
                    fontSize: 17,
                    symbol: state.returnSymbol,
                    isAction: state.returnIsAction,
                    label: state.returnTitle
                ),
                units: 2.25
            ))
        }

        let firstRow = state.layer == .emoji ? 3 : 0
        let allRows = rows + [bottom]
        var specs: [KeySpec] = []
        for (offset, row) in allRows.enumerated() {
            let index = firstRow + offset
            let top = topPadding + CGFloat(index) * rowHeight
            let cellTop = index == 0 ? 0 : top
            let cellBottom = index == 3 ? height : top + rowHeight
            var x = margin
            for (position, item) in row.enumerated() {
                let w = item.units * unit
                var spec = item.spec
                let left = position == 0 ? 0 : x
                let right = position == row.count - 1 ? width : x + w
                spec.cell = CGRect(x: left, y: cellTop, width: right - left, height: cellBottom - cellTop)
                spec.face = CGRect(
                    x: x + insetX + item.lead,
                    y: top + insetY,
                    width: w - insetX * 2 - item.lead - item.trail,
                    height: rowHeight - insetY * 2
                )
                specs.append(spec)
                x += w
            }
        }
        return specs
    }
}
