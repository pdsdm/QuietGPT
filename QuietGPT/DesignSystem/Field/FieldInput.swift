import CoreMotion
import Observation
import UIKit

@Observable
final class FieldInput {
    static let shared = FieldInput()

    private(set) var tilt: CGPoint = .zero
    @ObservationIgnored private(set) var gravity = CGPoint(x: 0, y: 0.8)
    private var touchPoint: CGPoint = .zero
    private var touchDown: Date?
    private var touchUp: Date?

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var users = 0
    @ObservationIgnored private var rest: CGPoint?

    func start() {
        users += 1
        guard users == 1, motion.isDeviceMotionAvailable, !UIAccessibility.isReduceMotionEnabled else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(to: .main) { data, _ in
            guard let gravity = data?.gravity else { return }
            MainActor.assumeIsolated {
                FieldInput.shared.update(gravity: CGPoint(x: gravity.x, y: gravity.y))
            }
        }
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        motion.stopDeviceMotionUpdates()
        rest = nil
        tilt = .zero
    }

    func touchBegan(at point: CGPoint) {
        touchPoint = point
        touchDown = .now
        touchUp = nil
    }

    func touchMoved(to point: CGPoint) {
        touchPoint = point
    }

    func touchEnded() {
        guard touchDown != nil else { return }
        touchUp = .now
    }

    func touch(at date: Date) -> (point: CGPoint, strength: Double) {
        guard let touchDown else { return (touchPoint, 0) }
        let grow = min(1, max(0, date.timeIntervalSince(touchDown) / 0.35))
        var strength = grow * grow * (3 - 2 * grow)
        if let touchUp {
            let fade = min(1, max(0, date.timeIntervalSince(touchUp) / 0.8))
            strength *= 1 - fade * fade * (3 - 2 * fade)
        }
        return (touchPoint, strength)
    }

    private func update(gravity: CGPoint) {
        self.gravity = CGPoint(x: self.gravity.x + (gravity.x - self.gravity.x) * 0.3, y: self.gravity.y + (-gravity.y - self.gravity.y) * 0.3)
        let base = rest ?? gravity
        let settled = CGPoint(x: base.x + (gravity.x - base.x) * 0.0015, y: base.y + (gravity.y - base.y) * 0.0015)
        rest = settled
        let target = CGPoint(x: clamp((gravity.x - settled.x) * 2.5), y: clamp((settled.y - gravity.y) * 2.5))
        tilt = CGPoint(x: tilt.x + (target.x - tilt.x) * 0.25, y: tilt.y + (target.y - tilt.y) * 0.25)
    }

    private func clamp(_ value: Double) -> Double {
        min(1, max(-1, value))
    }
}
