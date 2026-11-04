import SwiftUI
import UIKit

struct KeyboardTapCatcher: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardTapView {
        KeyboardTapView()
    }

    func updateUIView(_ uiView: KeyboardTapView, context: Context) {}
}

final class KeyboardTapView: UIView, UIGestureRecognizerDelegate {
    private lazy var tap: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(hideKeyboard))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        tap.view?.removeGestureRecognizer(tap)
        window?.addGestureRecognizer(tap)
    }

    @objc private func hideKeyboard() {
        KeyboardDismissal.hide()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard window?.rootViewController?.presentedViewController == nil else { return false }
        var view = touch.view
        while let current = view {
            if current is UITextInput { return false }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
