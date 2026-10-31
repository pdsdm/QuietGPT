import OSLog
import SwiftUI
import UIKit

final class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

final class KeyboardViewController: UIInputViewController {
    private static let logger = Logger(subsystem: "com.pdsdm.hush", category: "keyboard")
    private static let pinnedKey = "pinnedTone"

    private let model = KeyboardModel()
    private let rewriter = Rewriter()
    private var task: Task<Void, Never>?
    private var hintReset: Task<Void, Never>?
    private var last: (original: String, written: String)?
    private var draft: (original: String, shown: String)?
    private var lastSpace: ContinuousClock.Instant?
    private var lastShiftTap: ContinuousClock.Instant?

    override func loadView() {
        let input = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
        input.allowsSelfSizing = true
        inputView = input
        view = input
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let keyboard = UIHostingController(rootView: KeyboardView(model: model, actions: actions))
        keyboard.view.backgroundColor = .clear
        keyboard.sizingOptions = []
        addChild(keyboard)
        keyboard.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboard.view)
        let height = view.heightAnchor.constraint(equalToConstant: KeyboardView.height)
        height.priority = .defaultHigh + 1
        NSLayoutConstraint.activate([
            keyboard.view.topAnchor.constraint(equalTo: view.topAnchor),
            keyboard.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            keyboard.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            height
        ])
        keyboard.didMove(toParent: self)

        let language = Locale.preferredLanguages.first ?? "en"
        model.isSpanish = language.hasPrefix("es") || language.hasPrefix("ca")
        primaryLanguage = model.isSpanish ? "es-ES" : "en-US"
        updateReturnKey()

        model.pinned = UserDefaults.standard.string(forKey: Self.pinnedKey).flatMap(RewriteTone.init(rawValue:))
        rewriter.prepare()
        Self.logger.notice("Keyboard loaded, rewriter available: \(self.rewriter.isAvailable, privacy: .public)")
        if !rewriter.isAvailable {
            model.hint = "Apple Intelligence is off"
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    override func viewWillLayoutSubviews() {
        model.showsGlobe = needsInputModeSwitchKey
        super.viewWillLayoutSubviews()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        refresh()
    }

    private var actions: KeyboardActions {
        KeyboardActions(
            insert: { [weak self] in self?.insert($0) },
            deleteBackward: { [weak self] in self?.deleteBackward() },
            deleteWord: { [weak self] in self?.deleteWord() },
            space: { [weak self] in self?.space() },
            newline: { [weak self] in self?.newline() },
            shift: { [weak self] in self?.tapShift() },
            show: { [weak self] in self?.show($0) },
            nextKeyboard: { [weak self] in self?.advanceToNextInputMode() },
            trackpad: { [weak self] in self?.model.isTrackpad = $0 },
            moveCursor: { [weak self] in self?.moveCursor($0) },
            rewrite: { [weak self] in self?.rewrite(as: $0) },
            pin: { [weak self] in self?.pin($0) },
            ask: { [weak self] in self?.toggleAsk() },
            submitAsk: { [weak self] in self?.submitAsk() },
            undo: { [weak self] in self?.undo() }
        )
    }

    private var proxy: UITextDocumentProxy { textDocumentProxy }

    private func refresh() {
        updateShift()
        updateReturnKey()
    }

    private func click() {
        UIDevice.current.playInputClick()
    }

    private func insert(_ text: String) {
        stopWriting()
        let value = model.layer == .letters && model.shift != .off ? text.uppercased() : text
        if model.isAsking {
            model.instruction += value
        } else {
            proxy.insertText(value)
            forgetUndo()
        }
        if model.shift == .once {
            model.shift = .off
        }
        updateShift()
    }

    private func deleteBackward() {
        stopWriting()
        if model.isAsking {
            if !model.instruction.isEmpty {
                model.instruction.removeLast()
            }
            return
        }
        proxy.deleteBackward()
        forgetUndo()
        updateShift()
    }

    private func deleteWord() {
        stopWriting()
        if model.isAsking {
            let trimmed = model.instruction.replacing(/\s+$/, with: "")
            model.instruction = String(trimmed.dropLast(trimmed.reversed().prefix { !$0.isWhitespace }.count))
            return
        }
        let before = proxy.documentContextBeforeInput ?? ""
        let spaces = before.reversed().prefix { $0.isWhitespace }.count
        let word = before.dropLast(spaces).reversed().prefix { !$0.isWhitespace }.count
        for _ in 0..<max(1, spaces + word) {
            proxy.deleteBackward()
        }
        forgetUndo()
        updateShift()
    }

    private func space() {
        stopWriting()
        if model.isAsking {
            model.instruction += " "
            return
        }
        let before = proxy.documentContextBeforeInput ?? ""
        if let lastSpace, lastSpace.duration(to: .now) < .milliseconds(450),
           before.hasSuffix(" "), let previous = before.dropLast().last, previous.isLetter || previous.isNumber {
            proxy.deleteBackward()
            proxy.insertText(". ")
            self.lastSpace = nil
        } else {
            proxy.insertText(" ")
            lastSpace = .now
        }
        forgetUndo()
        model.layer = .letters
        updateShift()
    }

    private func newline() {
        stopWriting()
        if model.isAsking {
            submitAsk()
            return
        }
        proxy.insertText("\n")
        forgetUndo()
        updateShift()
    }

    private func moveCursor(_ steps: Int) {
        guard !model.isWriting, !model.isAsking else { return }
        proxy.adjustTextPosition(byCharacterOffset: steps)
        updateShift()
    }

    private func tapShift() {
        switch model.layer {
        case .letters:
            let now = ContinuousClock.now
            if let lastShiftTap, lastShiftTap.duration(to: now) < .milliseconds(350) {
                model.shift = .locked
                self.lastShiftTap = nil
                return
            }
            lastShiftTap = now
            model.shift = model.shift == .off ? .once : .off
        case .numbers:
            model.layer = .symbols
        case .symbols:
            model.layer = .numbers
        }
    }

    private func show(_ layer: KeyboardModel.Layer) {
        model.layer = layer
        if layer == .letters {
            updateShift()
        }
    }

    private func updateShift() {
        guard model.shift != .locked else { return }
        model.shift = shouldCapitalize ? .once : .off
    }

    private var shouldCapitalize: Bool {
        if model.isAsking {
            return model.instruction.isEmpty
        }
        let before = proxy.documentContextBeforeInput ?? ""
        switch proxy.autocapitalizationType ?? .sentences {
        case .none:
            return false
        case .allCharacters:
            return true
        case .words:
            return before.isEmpty || before.last?.isWhitespace == true
        case .sentences:
            break
        @unknown default:
            break
        }
        if before.isEmpty || before.last?.isNewline == true {
            return true
        }
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        guard before.last == " " else { return false }
        guard let mark = trimmed.last else { return true }
        return ".!?¡¿".contains(mark)
    }

    private func updateReturnKey() {
        switch proxy.returnKeyType ?? .default {
        case .go: setReturn("go", "ir", action: true)
        case .send: setReturn("send", "enviar", action: true)
        case .search, .google, .yahoo: setReturn("search", "buscar", action: true)
        case .done: setReturn("done", "OK", action: true)
        case .join: setReturn("join", "unirse", action: true)
        case .route: setReturn("route", "ruta", action: true)
        case .next: setReturn("next", "siguiente", action: false)
        case .continue: setReturn("continue", "continuar", action: false)
        default: setReturn("return", "intro", action: false)
        }
    }

    private func setReturn(_ english: String, _ spanish: String, action: Bool) {
        model.returnTitle = model.isSpanish ? spanish : english
        model.returnIsAction = action
    }

    private func toggleAsk() {
        click()
        model.isAsking.toggle()
        model.instruction = ""
        model.layer = .letters
        updateShift()
    }

    private func submitAsk() {
        click()
        let instruction = model.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        model.isAsking = false
        model.instruction = ""
        updateShift()
        guard !instruction.isEmpty else { return }
        run(request: instruction, tone: nil)
    }

    private func pin(_ tone: RewriteTone) {
        model.pinned = model.pinned == tone ? nil : tone
        UserDefaults.standard.set(model.pinned?.rawValue, forKey: Self.pinnedKey)
        show(hint: model.pinned == nil ? "unpinned" : "\(tone.title.lowercased()) pinned first")
    }

    private func rewrite(as tone: RewriteTone) {
        run(request: tone.request, tone: tone)
    }

    private func run(request: String, tone: RewriteTone?) {
        guard !model.isWriting else { return }
        let (text, isSelection) = currentText()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            show(hint: "write a message first")
            return
        }
        guard rewriter.isAvailable else {
            show(hint: "Apple Intelligence is off")
            return
        }

        task?.cancel()
        hintReset?.cancel()
        forgetUndo()
        model.tone = tone
        model.isWriting = true
        model.hint = "writing on this iPhone…"
        let stream = rewriter.rewrite(text, request: request)
        task = Task {
            do {
                for try await snapshot in stream {
                    guard !Task.isCancelled else { return }
                    let next = String(snapshot.drop { $0.isWhitespace })
                    guard !next.isEmpty else { continue }
                    if draft == nil {
                        clear(text, isSelection: isSelection)
                        draft = (text, "")
                    }
                    write(next)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                Self.logger.error("Rewrite failed: \(String(describing: error), privacy: .public)")
                restore()
                model.isWriting = false
                model.tone = nil
                show(hint: Rewriter.message(for: error))
                return
            }
            guard !Task.isCancelled else { return }

            let written = (draft?.shown ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !written.isEmpty else {
                restore()
                model.isWriting = false
                model.tone = nil
                show(hint: "nothing came back, try again")
                return
            }
            write(written)
            draft = nil
            last = (text, written)
            model.isWriting = false
            model.canUndo = true
            show(hint: "rewritten on this iPhone")
            Self.logger.notice("Rewrite done, \(written.count, privacy: .public) characters")
        }
    }

    private func clear(_ text: String, isSelection: Bool) {
        guard !isSelection else { return }
        let after = proxy.documentContextAfterInput ?? ""
        if !after.isEmpty {
            proxy.adjustTextPosition(byCharacterOffset: after.count)
        }
        for _ in 0..<text.count {
            proxy.deleteBackward()
        }
    }

    private func write(_ next: String) {
        guard let draft else { return }
        let common = zip(draft.shown, next).prefix { $0 == $1 }.count
        for _ in 0..<(draft.shown.count - common) {
            proxy.deleteBackward()
        }
        let rest = String(next.dropFirst(common))
        if !rest.isEmpty {
            proxy.insertText(rest)
        }
        self.draft?.shown = next
    }

    private func restore() {
        guard let draft else { return }
        for _ in 0..<draft.shown.count {
            proxy.deleteBackward()
        }
        proxy.insertText(draft.original)
        self.draft = nil
    }

    private func stopWriting() {
        guard model.isWriting else { return }
        task?.cancel()
        task = nil
        restore()
        model.isWriting = false
        model.tone = nil
        show(hint: "stopped, your text is back")
    }

    private func undo() {
        click()
        guard let last else { return }
        replace(last.written, isSelection: false, with: last.original)
        forgetUndo()
        show(hint: "back to your text")
    }

    private func forgetUndo() {
        guard last != nil || model.tone != nil else { return }
        last = nil
        model.canUndo = false
        model.tone = nil
    }

    private func show(hint: String) {
        hintReset?.cancel()
        model.hint = hint
        hintReset = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !model.isWriting else { return }
            model.hint = rewriter.isAvailable ? "pick a tone or ask" : "Apple Intelligence is off"
        }
    }

    private func currentText() -> (String, Bool) {
        if let selected = proxy.selectedText, !selected.isEmpty {
            return (selected, true)
        }
        return ((proxy.documentContextBeforeInput ?? "") + (proxy.documentContextAfterInput ?? ""), false)
    }

    private func replace(_ old: String, isSelection: Bool, with new: String) {
        if !isSelection {
            let after = proxy.documentContextAfterInput ?? ""
            if !after.isEmpty {
                proxy.adjustTextPosition(byCharacterOffset: after.count)
            }
            for _ in 0..<old.count {
                proxy.deleteBackward()
            }
        }
        proxy.insertText(new)
    }
}
