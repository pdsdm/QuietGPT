import Foundation

@Observable
final class KeyboardModel {
    enum Layer {
        case letters
        case numbers
        case symbols
    }

    enum Shift {
        case off
        case once
        case locked
    }

    var layer = Layer.letters
    var shift = Shift.once
    var tone: RewriteTone?
    var pinned: RewriteTone?
    var hint = "pick a tone or ask"
    var isWriting = false
    var canUndo = false
    var isAsking = false
    var instruction = ""
    var showsGlobe = false
    var returnTitle = "return"
    var returnIsAction = false

    var tones: [RewriteTone] {
        guard let pinned else { return RewriteTone.allCases }
        return [pinned] + RewriteTone.allCases.filter { $0 != pinned }
    }
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
    var rewrite: (RewriteTone) -> Void
    var pin: (RewriteTone) -> Void
    var ask: () -> Void
    var submitAsk: () -> Void
    var undo: () -> Void
}
