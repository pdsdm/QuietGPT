import Foundation

@Observable
final class KeyboardModel {
    enum Layer {
        case letters
        case numbers
        case symbols
        case emoji
    }

    enum Shift {
        case off
        case once
        case locked
    }

    var layer = Layer.letters
    var shift = Shift.once
    var styles: [RewriteStyle] = []
    var active: RewriteStyle.ID?
    var hint: String?
    var isWriting = false
    var canUndo = false
    var isAsking = false
    var instruction = ""
    var showsGlobe = false
    var returnTitle = "return"
    var returnSymbol: String? = "return.left"
    var returnIsAction = false
    var isSpanish = false
    var showsAsk = true
    var showsPanel = false
    var options = KeyboardOptions()

    var goTitle: String { KeyboardText.string("go") }

    var keys: KeyState {
        KeyState(
            layer: layer,
            shift: shift,
            isSpanish: isSpanish,
            showsGlobe: showsGlobe,
            returnTitle: isAsking ? goTitle : returnTitle,
            returnSymbol: isAsking ? nil : returnSymbol,
            returnIsAction: isAsking || returnIsAction
        )
    }
}

struct KeyState: Equatable {
    var layer: KeyboardModel.Layer
    var shift: KeyboardModel.Shift
    var isSpanish: Bool
    var showsGlobe: Bool
    var returnTitle: String
    var returnSymbol: String?
    var returnIsAction: Bool
}

struct KeyboardActions {
    var insert: (String) -> Void
    var deleteBackward: () -> Void
    var deleteWord: () -> Void
    var space: () -> Void
    var newline: () -> Void
    var shift: () -> Void
    var show: (KeyboardModel.Layer) -> Void
    var nextKeyboard: () -> Void
    var moveCursor: (Int) -> Void
    var openPanel: () -> Void
}

struct BarActions {
    var rewrite: (RewriteStyle) -> Void
    var ask: () -> Void
    var submitAsk: () -> Void
    var stop: () -> Void
    var undo: () -> Void
    var close: () -> Void
    var setLanguage: (KeyboardLanguage) -> Void
    var setAutoCapitalize: (Bool) -> Void
    var setPeriodShortcut: (Bool) -> Void
}
