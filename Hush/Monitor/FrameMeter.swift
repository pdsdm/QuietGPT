import QuartzCore

final class FrameMeter: NSObject {
    private var link: CADisplayLink?
    private var frames = 0
    private var since = CACurrentMediaTime()

    func start() {
        guard link == nil else { return }
        frames = 0
        since = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    func take() -> Double {
        let now = CACurrentMediaTime()
        let elapsed = now - since
        let rate = elapsed > 0 ? Double(frames) / elapsed : 0
        frames = 0
        since = now
        return rate
    }

    @objc private func tick() {
        frames += 1
    }
}
