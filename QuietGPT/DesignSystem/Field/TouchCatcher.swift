import SwiftUI
import UIKit

struct TouchCatcher: UIViewRepresentable {
    func makeUIView(context: Context) -> CatcherView {
        CatcherView()
    }

    func updateUIView(_ uiView: CatcherView, context: Context) {}

    final class CatcherView: UIView, UIGestureRecognizerDelegate {
        private var recognizer: UILongPressGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, recognizer == nil else { return }
            let press = UILongPressGestureRecognizer(target: self, action: #selector(track(_:)))
            press.minimumPressDuration = 0
            press.cancelsTouchesInView = false
            press.delaysTouchesBegan = false
            press.delaysTouchesEnded = false
            press.delegate = self
            window.addGestureRecognizer(press)
            recognizer = press
        }

        @objc private func track(_ press: UILongPressGestureRecognizer) {
            let point = press.location(in: press.view)
            switch press.state {
            case .began: FieldInput.shared.touchBegan(at: point)
            case .changed: FieldInput.shared.touchMoved(to: point)
            case .ended, .cancelled, .failed: FieldInput.shared.touchEnded()
            default: break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
