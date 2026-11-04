import OSLog
import SwiftUI
import UIKit

final class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

final class KeyboardViewController: UIInputViewController {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "quietgpt", category: "keyboard")
    private static let doubleSpaceWindow = Duration.milliseconds(450)
    private static let doubleShiftWindow = Duration.milliseconds(350)
    private static let hintDuration = Duration.seconds(2.5)

    private let model = KeyboardModel()
    private let rewriter = Rewriter()
    private let keys = KeysView()
    private var bar: UIHostingController<QuietGPTBar>?
    private let emoji = EmojiPanel()
    private var panel: UIHostingController<QuietGPTPanel>?
    private var mode = (panel: false, bar: false)
    private var options = KeyboardOptions()
    private var task: Task<Void, Never>?
    private var hintReset: Task<Void, Never>?
    private var last: (original: String, written: String)?
    private var draft: (original: String, shown: String)?
    private var lastSpace: ContinuousClock.Instant?
    private var lastShiftTap: ContinuousClock.Instant?
    private var height: NSLayoutConstraint?

    override func loadView() {
        let input = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
        input.allowsSelfSizing = true
        inputView = input
        view = input
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let bar = UIHostingController(rootView: QuietGPTBar(model: model, actions: barActions))
        bar.view.backgroundColor = .clear
        bar.sizingOptions = []
        addChild(bar)
        view.addSubview(bar.view)
        bar.didMove(toParent: self)
        self.bar = bar

        emoji.onInsert = { [weak self] in self?.insert($0) }
        emoji.isHidden = true
        view.addSubview(emoji)

        keys.actions = keyActions
        view.addSubview(keys)

        let panel = UIHostingController(rootView: QuietGPTPanel(model: model, actions: barActions))
        panel.view.backgroundColor = .clear
        panel.sizingOptions = []
        panel.safeAreaRegions = []
        panel.view.isHidden = true
        addChild(panel)
        view.addSubview(panel.view)
        panel.didMove(toParent: self)
        self.panel = panel

        loadSettings()
        updateReturnKey()
        observe()
        rewriter.prepare()
        Self.logger.notice("Keyboard loaded, rewriter available: \(self.rewriter.isAvailable, privacy: .public)")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if height == nil {
            let sizer = UIView()
            sizer.translatesAutoresizingMaskIntoConstraints = false
            sizer.isUserInteractionEnabled = false
            view.insertSubview(sizer, at: 0)
            let height = sizer.heightAnchor.constraint(equalToConstant: KeyLayout.height + KeyLayout.bottomPadding)
            height.priority = .required - 1
            NSLayoutConstraint.activate([
                sizer.topAnchor.constraint(equalTo: view.topAnchor),
                sizer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                sizer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                sizer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                height
            ])
            self.height = height
        }
        updateHeight()
        loadSettings()
        refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        for recognizer in view.window?.gestureRecognizers ?? [] {
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let barHeight = mode.bar ? QuietGPTBar.height : 0
        let space = view.bounds.height - barHeight - KeyLayout.topPadding - KeyLayout.bottomPadding
        let rowHeight = space > 0 ? min(KeyLayout.rowHeight, space / 4) : KeyLayout.rowHeight
        let keysHeight = KeyLayout.height(rowHeight: rowHeight)
        let top = view.bounds.height - keysHeight - KeyLayout.bottomPadding
        bar?.view.frame = CGRect(x: 0, y: top - QuietGPTBar.height, width: width, height: QuietGPTBar.height)
        bar?.view.isHidden = !mode.bar
        emoji.frame = view.bounds
        emoji.gridHeight = top + KeyLayout.topPadding + rowHeight * 3
        keys.rowHeight = rowHeight
        keys.topLimit = -top
        keys.frame = CGRect(x: 0, y: top, width: width, height: keysHeight)
        var state = model.keys
        state.layer = .letters
        if let lock = KeyLayout.build(state, width: width, rowHeight: rowHeight).first(where: { $0.kind == .quietGPT }) {
            let frame = lock.face.offsetBy(dx: 0, dy: top)
            if model.closeFrame != frame {
                model.closeFrame = frame
            }
        }
        state.layer = .emoji
        let specs = KeyLayout.build(state, width: width, rowHeight: rowHeight)
        if let delete = specs.first(where: { $0.kind == .delete }), let left = specs.dropLast().map(\.cell.maxX).max() {
            emoji.barFrame = CGRect(x: left, y: top + delete.face.minY, width: delete.cell.minX - left, height: delete.face.height)
        }
        keys.isHidden = mode.panel
        panel?.view.frame = view.bounds
        panel?.view.isHidden = !mode.panel
    }

    override func viewWillLayoutSubviews() {
        model.showsGlobe = needsInputModeSwitchKey
        updateHeight()
        super.viewWillLayoutSubviews()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        refresh()
    }

    private func observe() {
        withObservationTracking {
            keys.state = model.keys
            let showsEmoji = model.layer == .emoji && !model.showsPanel
            if showsEmoji && emoji.isHidden {
                emoji.refresh()
            }
            emoji.isHidden = !showsEmoji
            updateHeight()
            apply(panel: model.showsPanel, bar: model.isAsking)
        } onChange: { [weak self] in
            let controller = self
            Task { @MainActor in controller?.observe() }
        }
    }

    private func updateHeight() {
        let base = KeyLayout.height + KeyLayout.bottomPadding
        let wanted = emoji.isHidden ? base : base + KeyLayout.emojiExtra
        let screen = view.window?.windowScene?.screen.bounds.height ?? .infinity
        height?.constant = min(wanted, screen * KeyLayout.maxScreenShare)
    }

    private func apply(panel: Bool, bar: Bool) {
        guard mode != (panel, bar) else { return }
        mode = (panel, bar)
        UIView.transition(with: view, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
    }

    private func loadSettings() {
        options = StyleStore.options
        applyOptions()
        model.styles = StyleStore.enabledStyles
        model.people = StyleStore.enabledPeople
        model.ruleCount = min(StyleStore.rules.count, StyleStore.maxRules)
        model.showsAsk = options.showsAsk
    }

    private func applyOptions() {
        model.options = options
        model.isSpanish = options.language.isSpanish
        primaryLanguage = model.isSpanish ? "es-ES" : "en-US"
        KeyboardText.use(spanish: model.isSpanish)
    }

    private func change(_ update: (inout KeyboardOptions) -> Void) {
        UIDevice.current.playInputClick()
        update(&options)
        StyleStore.options = options
        applyOptions()
        refresh()
    }

    private func openPanel() {
        model.layer = .letters
        model.showsPanel = true
    }

    private func closePanel() {
        UIDevice.current.playInputClick()
        model.showsPanel = false
        updateShift()
    }

    private var keyActions: KeyboardActions {
        KeyboardActions(
            insert: { [weak self] in self?.insert($0) },
            deleteBackward: { [weak self] in self?.deleteBackward() },
            deleteWord: { [weak self] in self?.deleteWord() },
            space: { [weak self] in self?.space() },
            newline: { [weak self] in self?.newline() },
            shift: { [weak self] in self?.tapShift() },
            show: { [weak self] in self?.show($0) },
            nextKeyboard: { [weak self] in self?.advanceToNextInputMode() },
            moveCursor: { [weak self] in self?.moveCursor($0) },
            openPanel: { [weak self] in self?.openPanel() }
        )
    }

    private var barActions: BarActions {
        BarActions(
            rewrite: { [weak self] in self?.rewrite(as: $0) },
            ask: { [weak self] in self?.toggleAsk() },
            submitAsk: { [weak self] in self?.submitAsk() },
            stop: { [weak self] in self?.stopWriting() },
            undo: { [weak self] in self?.undo() },
            close: { [weak self] in self?.closePanel() },
            setLanguage: { [weak self] language in self?.change { $0.language = language } }
        )
    }

    private var proxy: UITextDocumentProxy { textDocumentProxy }

    private func refresh() {
        updateShift()
        updateReturnKey()
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
        if options.periodShortcut, let lastSpace, lastSpace.duration(to: .now) < Self.doubleSpaceWindow,
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
            if let lastShiftTap, lastShiftTap.duration(to: now) < Self.doubleShiftWindow {
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
        case .emoji:
            break
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
        guard options.autoCapitalize else { return false }
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
        case .send: setReturn("send", symbol: "arrow.up", action: true)
        case .search, .google, .yahoo: setReturn("search", action: true)
        case .done: setReturn("done", action: true)
        case .join: setReturn("join", action: true)
        case .route: setReturn("route", action: true)
        case .next: setReturn("next", action: false)
        case .continue: setReturn("continue", action: false)
        default: setReturn("return", symbol: "return.left", action: false)
        }
    }

    private func setReturn(_ title: String.LocalizationValue, symbol: String? = nil, action: Bool) {
        model.returnTitle = KeyboardText.string(title)
        model.returnSymbol = symbol
        model.returnIsAction = action
    }

    private func toggleAsk() {
        stopWriting()
        model.isAsking.toggle()
        model.showsPanel = !model.isAsking
        model.instruction = ""
        model.layer = .letters
        updateShift()
    }

    private func submitAsk() {
        UIDevice.current.playInputClick()
        let instruction = model.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        model.isAsking = false
        model.showsPanel = true
        model.instruction = ""
        updateShift()
        guard !instruction.isEmpty else { return }
        run(request: instruction, style: nil)
    }

    private func rewrite(as style: RewriteStyle) {
        run(request: style.prompt, style: style)
    }

    private func run(request: String, style: RewriteStyle?) {
        guard !model.isWriting else { return }
        let (text, isSelection) = currentText()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            show(hint: KeyboardText.string("Write a message first"))
            return
        }
        guard rewriter.isAvailable else {
            show(hint: "Apple Intelligence is off")
            return
        }

        task?.cancel()
        hintReset?.cancel()
        model.hint = nil
        forgetUndo()
        model.active = style?.id
        model.isWriting = true
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
                finishWriting()
                show(hint: Rewriter.message(for: error))
                return
            }
            guard !Task.isCancelled else { return }

            let written = (draft?.shown ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !written.isEmpty else {
                restore()
                finishWriting()
                show(hint: "Nothing came back, try again")
                return
            }
            write(written)
            draft = nil
            last = (text, written)
            finishWriting()
            model.canUndo = true
            Self.logger.notice("Rewrite done, \(written.count, privacy: .public) characters")
        }
    }

    private func finishWriting() {
        model.isWriting = false
        model.active = nil
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
        finishWriting()
        show(hint: KeyboardText.string("Stopped, your text is back"))
    }

    private func undo() {
        guard let last else { return }
        replace(last.written, isSelection: false, with: last.original)
        forgetUndo()
    }

    private func forgetUndo() {
        guard last != nil || model.canUndo else { return }
        last = nil
        model.canUndo = false
    }

    private func show(hint: String) {
        hintReset?.cancel()
        model.hint = hint
        hintReset = Task {
            try? await Task.sleep(for: Self.hintDuration)
            guard !Task.isCancelled else { return }
            model.hint = nil
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
