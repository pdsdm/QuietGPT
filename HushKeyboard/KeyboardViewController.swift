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
        click()
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
        click()
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
        click()
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
        click()
        if model.isAsking {
            submitAsk()
            return
        }
        proxy.insertText("\n")
        forgetUndo()
        updateShift()
    }

    private func tapShift() {
        click()
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
        click()
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
        case .go: setReturn("go", action: true)
        case .send: setReturn("send", action: true)
        case .search, .google, .yahoo: setReturn("search", action: true)
        case .done: setReturn("done", action: true)
        case .join: setReturn("join", action: true)
        case .route: setReturn("route", action: true)
        case .next: setReturn("next", action: false)
        case .continue: setReturn("continue", action: false)
        default: setReturn("return", action: false)
        }
    }

    private func setReturn(_ title: String, action: Bool) {
        model.returnTitle = title
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
        model.tone = tone
        model.isWriting = true
        model.hint = "writing on this iPhone…"
        let stream = rewriter.rewrite(text, request: request)
        task = Task {
            var result = ""
            do {
                for try await snapshot in stream {
                    result = snapshot
                }
            } catch is CancellationError {
                return
            } catch {
                Self.logger.error("Rewrite failed: \(String(describing: error), privacy: .public)")
                model.isWriting = false
                model.tone = nil
                show(hint: Rewriter.message(for: error))
                return
            }

            let written = result.trimmingCharacters(in: .whitespacesAndNewlines)
            replace(text, isSelection: isSelection, with: written)
            last = (text, written)
            model.isWriting = false
            model.canUndo = true
            show(hint: "rewritten on this iPhone")
            Self.logger.notice("Rewrite done, \(written.count, privacy: .public) characters")
        }
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
