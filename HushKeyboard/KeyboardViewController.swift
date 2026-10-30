import OSLog
import SwiftUI
import UIKit

@Observable
final class KeyboardModel {
    var tone: RewriteTone?
    var status = "pick a tone"
    var isWriting = false
    var canUndo = false
    var showsGlobe = true
}

final class KeyboardViewController: UIInputViewController {
    private static let logger = Logger(subsystem: "com.pdsdm.hush", category: "keyboard")

    private let model = KeyboardModel()
    private let rewriter = Rewriter()
    private var task: Task<Void, Never>?
    private var last: (original: String, written: String)?

    override func viewDidLoad() {
        super.viewDidLoad()

        let bar = UIHostingController(rootView: ToneBar(
            model: model,
            onTone: { [weak self] in self?.rewrite(as: $0) },
            onUndo: { [weak self] in self?.undo() },
            onNextKeyboard: { [weak self] in self?.advanceToNextInputMode() }
        ))
        bar.view.backgroundColor = .clear
        addChild(bar)
        bar.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar.view)
        NSLayoutConstraint.activate([
            bar.view.topAnchor.constraint(equalTo: view.topAnchor),
            bar.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bar.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            view.heightAnchor.constraint(equalToConstant: 112)
        ])
        bar.didMove(toParent: self)

        rewriter.prepare()
        Self.logger.notice("Keyboard loaded, rewriter available: \(self.rewriter.isAvailable, privacy: .public)")
        if !rewriter.isAvailable {
            model.status = "Apple Intelligence is off"
        }
    }

    override func viewWillLayoutSubviews() {
        model.showsGlobe = needsInputModeSwitchKey
        super.viewWillLayoutSubviews()
    }

    private func rewrite(as tone: RewriteTone) {
        let (text, isSelection) = currentText()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            model.status = "write a message first"
            return
        }
        guard rewriter.isAvailable else {
            model.status = "Apple Intelligence is off"
            return
        }

        task?.cancel()
        model.tone = tone
        model.isWriting = true
        model.status = "writing…"
        let stream = rewriter.rewrite(text, tone: tone)
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
                model.status = Rewriter.message(for: error)
                model.isWriting = false
                model.tone = nil
                return
            }

            let written = result.trimmingCharacters(in: .whitespacesAndNewlines)
            replace(text, isSelection: isSelection, with: written)
            last = (text, written)
            model.isWriting = false
            model.canUndo = true
            model.status = "rewritten on this iPhone"
        }
    }

    private func undo() {
        guard let last else { return }
        replace(last.written, isSelection: false, with: last.original)
        self.last = nil
        model.canUndo = false
        model.tone = nil
        model.status = "pick a tone"
    }

    private func currentText() -> (String, Bool) {
        let proxy = textDocumentProxy
        if let selected = proxy.selectedText, !selected.isEmpty {
            return (selected, true)
        }
        return ((proxy.documentContextBeforeInput ?? "") + (proxy.documentContextAfterInput ?? ""), false)
    }

    private func replace(_ old: String, isSelection: Bool, with new: String) {
        let proxy = textDocumentProxy
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
