import OSLog
import UIKit

final class KeyCap: UIView {
    let label = UILabel()
    let icon = UIImageView()
    let badge = UILabel()
    var labelOffset: CGFloat = 0
    var onActivate: () -> Void = {}

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = KeyStyle.radius
        layer.cornerCurve = .continuous
        label.textAlignment = .center
        icon.contentMode = .center
        badge.font = .systemFont(ofSize: 13, weight: .regular, width: .condensed)
        addSubview(label)
        addSubview(icon)
        addSubview(badge)
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.sizeToFit()
        label.center = CGPoint(x: bounds.midX, y: bounds.midY + labelOffset)
        icon.frame = bounds
        badge.sizeToFit()
        badge.frame.origin = CGPoint(x: bounds.maxX - badge.bounds.width - 6, y: bounds.maxY - badge.bounds.height - 4)
    }

    override func accessibilityActivate() -> Bool {
        onActivate()
        return true
    }
}

final class Balloon: UIView {
    static let height: CGFloat = 65
    static let spread: CGFloat = 12
    static let gap: CGFloat = 4
    static let smallest: CGFloat = 40
    static let minimumTime: CFTimeInterval = 0.1

    private let label = UILabel()
    private var shownAt: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = 13
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.14
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        label.textAlignment = .center
        addSubview(label)
    }

    required init?(coder: NSCoder) { nil }

    func show(_ spec: KeySpec, limit: CGFloat, width: CGFloat, style: KeyStyle) {
        shownAt = CACurrentMediaTime()
        let face = spec.face
        let height = min(Self.height, max(face.minY - Self.gap - limit, Self.smallest))
        let wide = face.width + Self.spread * 2
        let x = min(max(face.midX - wide / 2, KeyLayout.margin), width - KeyLayout.margin - wide)
        frame = CGRect(x: x, y: max(limit, face.minY - Self.gap - height), width: wide, height: height)
        backgroundColor = style.popup
        layer.borderColor = style.outline.cgColor

        let text = spec.title ?? ""
        let lower = text.lowercased() == text && text.uppercased() != text
        label.text = text
        label.font = .systemFont(ofSize: max((lower ? 34 : 31) * height / Self.height, 28))
        label.textColor = style.text
        label.sizeToFit()
        label.center = CGPoint(x: bounds.midX, y: bounds.midY + (lower ? -2 : -1))
    }

    func dismiss() {
        let remaining = Self.minimumTime - (CACurrentMediaTime() - shownAt)
        guard remaining > 0 else {
            removeFromSuperview()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            self?.removeFromSuperview()
        }
    }
}

final class VariantsPanel: UIView {
    static let padding: CGFloat = 10
    static let gap: CGFloat = 5

    let options: [String]
    let opensLeft: Bool
    private let cell: CGSize
    private var labels: [UILabel] = []
    private let highlight = UIView()
    private let style: KeyStyle
    private(set) var choice = 0

    init(spec: KeySpec, options: [String], uppercase: Bool, bounds limits: ClosedRange<CGFloat>, top limit: CGFloat, style: KeyStyle) {
        self.options = options
        self.opensLeft = spec.opensLeft
        self.style = style
        let face = spec.face
        cell = CGSize(width: face.width + 4, height: face.height - 1)
        let width = CGFloat(options.count) * cell.width + Self.padding * 2
        let height = cell.height + Self.padding * 2
        var minX = opensLeft
            ? face.midX + cell.width / 2 + Self.padding - width
            : face.midX - cell.width / 2 - Self.padding
        minX = min(max(minX, limits.lowerBound), limits.upperBound - width)
        let minY = max(face.minY - Self.gap - height, limit)
        super.init(frame: CGRect(x: minX, y: minY, width: width, height: height))
        isUserInteractionEnabled = false
        backgroundColor = style.popup
        layer.cornerRadius = 11
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 1)

        highlight.backgroundColor = KeyStyle.blue
        highlight.layer.cornerRadius = 9
        highlight.layer.cornerCurve = .continuous
        addSubview(highlight)

        for (index, option) in options.enumerated() {
            let label = UILabel()
            let lower = !uppercase && option.lowercased() == option && option.uppercased() != option
            label.text = uppercase ? option.uppercased() : option
            label.font = .systemFont(ofSize: lower ? 24 : 22)
            label.textAlignment = .center
            label.frame = slot(index).offsetBy(dx: 0, dy: lower ? -2 : -1.2)
            addSubview(label)
            labels.append(label)
        }
        select(0)
    }

    required init?(coder: NSCoder) { nil }

    private func slot(_ index: Int) -> CGRect {
        let position = opensLeft ? options.count - 1 - index : index
        return CGRect(x: Self.padding + CGFloat(position) * cell.width, y: Self.padding, width: cell.width, height: cell.height)
    }

    func select(_ index: Int) {
        choice = index
        highlight.frame = slot(index)
        for (offset, label) in labels.enumerated() {
            label.textColor = offset == index ? .white : style.text
        }
    }

    func track(x: CGFloat) {
        let local = x - frame.minX - Self.padding
        let position = min(max(Int((local / cell.width).rounded(.down)), 0), options.count - 1)
        let index = opensLeft ? options.count - 1 - position : position
        if index != choice {
            select(index)
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

final class KeysView: UIView {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "quietgpt", category: "keys")

    private final class Press {
        var id: String
        let origin: KeyKind
        let startX: CGFloat
        var committed = false
        var fromSwitch = false
        var balloon: Balloon?
        var panel: VariantsPanel?
        var hold: Timer?
        var tracking = false
        var latest: CGFloat = 0
        var moved: CGFloat = 0

        init(id: String, origin: KeyKind, startX: CGFloat) {
            self.id = id
            self.origin = origin
            self.startX = startX
        }
    }

    var actions: KeyboardActions?
    var topLimit: CGFloat = 0
    var rowHeight = KeyLayout.rowHeight {
        didSet {
            guard rowHeight != oldValue else { return }
            rebuild()
        }
    }

    var state: KeyState? {
        didSet {
            guard state != oldValue else { return }
            rebuild()
        }
    }

    private var specs: [KeySpec] = []
    private var caps: [String: KeyCap] = [:]
    private var presses: [UITouch: Press] = [:]
    private var builtWidth: CGFloat = 0
    private var deleteTimer: Timer?
    private var deleteCount = 0
    private var isTracking = false

    private var style: KeyStyle { .current(traitCollection) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        clipsToBounds = false
        backgroundColor = UIColor(white: 1, alpha: 0.001)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: KeysView, _: UITraitCollection) in
            view.rebuild()
        }
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != builtWidth {
            rebuild()
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard bounds.contains(point) else { return false }
        return state?.layer != .emoji || specs.contains { $0.cell.contains(point) }
    }

    private func spec(_ id: String) -> KeySpec? {
        specs.first { $0.id == id }
    }

    private func key(at point: CGPoint) -> KeySpec? {
        if let hit = specs.first(where: { $0.cell.contains(point) }) {
            return hit
        }
        return specs.min { distance($0.cell, point) < distance($1.cell, point) }
    }

    private func distance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    private var uppercase: Bool {
        state?.layer == .letters && state?.shift != .off
    }

    private func rebuild() {
        guard let state else { return }
        builtWidth = bounds.width
        specs = KeyLayout.build(state, width: bounds.width, rowHeight: rowHeight)
        let style = style
        var next: [String: KeyCap] = [:]
        var spare = caps
        for spec in specs {
            let cap = spare.removeValue(forKey: spec.id) ?? KeyCap()
            if cap.superview == nil {
                insertSubview(cap, at: 0)
            }
            configure(cap, spec, style: style)
            next[spec.id] = cap
        }
        for cap in spare.values {
            cap.removeFromSuperview()
        }
        caps = next
        for press in presses.values {
            highlight(press.id, true)
        }
        accessibilityElements = specs.compactMap { caps[$0.id] }
    }

    private func configure(_ cap: KeyCap, _ spec: KeySpec, style: KeyStyle) {
        cap.frame = spec.face
        cap.backgroundColor = spec.isAction ? KeyStyle.blue : style.key
        let foreground = spec.isAction ? UIColor.white : style.text
        if spec.kind == .quietGPT {
            cap.icon.image = Self.mark(size: 30, style: style)
            cap.icon.overrideUserInterfaceStyle = .unspecified
            cap.icon.isHidden = false
            cap.label.isHidden = true
        } else if let symbol = spec.symbol {
            cap.icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: spec.symbolSize, weight: .regular))
            cap.icon.tintColor = foreground
            cap.icon.overrideUserInterfaceStyle = symbol.hasSuffix(".inverse") ? .light : .unspecified
            cap.icon.isHidden = false
            cap.label.isHidden = true
        } else {
            cap.icon.isHidden = true
            cap.label.isHidden = spec.title == nil
            cap.label.text = spec.title
            cap.label.font = .systemFont(ofSize: spec.fontSize)
            cap.label.textColor = foreground
            let lower = spec.character != nil && spec.fontSize == 24
            cap.labelOffset = spec.character == nil ? 0 : lower ? -1.7 : -0.9
        }
        cap.badge.text = spec.tag
        cap.badge.textColor = style.tag
        cap.badge.isHidden = spec.tag == nil
        let content: CGFloat = isTracking ? 0 : 1
        cap.label.alpha = content
        cap.icon.alpha = content
        cap.badge.alpha = content
        cap.accessibilityLabel = spec.label
        cap.onActivate = { [weak self] in self?.activate(spec) }
        cap.setNeedsLayout()
    }

    private static func mark(size: CGFloat, style: KeyStyle) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            let side = size * 0.56
            let rect = CGRect(x: (size - side) / 2, y: (size - side) / 2, width: side, height: side)
            style.text.setFill()
            UIBezierPath(cgPath: LockMark().path(in: rect).cgPath).fill()
        }
    }

    private func highlight(_ id: String, _ on: Bool) {
        guard let spec = spec(id), let cap = caps[id] else { return }
        let style = style
        if spec.character != nil {
            cap.backgroundColor = on && !isTracking ? style.lit : style.key
            return
        }
        if spec.kind == .space {
            cap.backgroundColor = on && !isTracking ? style.pressed : style.key
            return
        }
        if spec.isAction {
            cap.backgroundColor = on ? style.pressed : KeyStyle.blue
            let tint = on ? style.text : UIColor.white
            cap.label.textColor = tint
            cap.icon.tintColor = tint
        } else {
            cap.backgroundColor = on ? style.pressed : style.key
        }
        if spec.kind == .delete {
            cap.icon.image = UIImage(systemName: on ? "delete.left.fill" : "delete.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: spec.symbolSize, weight: .regular))
        }
    }

    private func activate(_ spec: KeySpec) {
        guard let actions else { return }
        UIDevice.current.playInputClick()
        switch spec.kind {
        case .character(let value): actions.insert(value)
        case .shift, .symbols: actions.shift()
        case .delete: actions.deleteBackward()
        case .layer(let target), .emoji(let target): actions.show(target)
        case .globe: actions.nextKeyboard()
        case .space: actions.space()
        case .enter: actions.newline()
        case .quietGPT: actions.openPanel()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            commitPending()
            guard let spec = key(at: point) else { continue }
            let press = Press(id: spec.id, origin: spec.kind, startX: point.x)
            presses[touch] = press
            UIDevice.current.playInputClick()
            begin(press, spec)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let press = presses[touch] else { continue }
            let point = touch.location(in: self)
            if let panel = press.panel {
                panel.track(x: point.x)
                continue
            }
            if press.origin == .space {
                track(press, x: point.x)
                continue
            }
            guard !press.committed, let target = key(at: point), target.id != press.id, target.character != nil else { continue }
            let current = spec(press.id)
            let slides: Bool = switch press.origin {
            case .character, .shift, .layer, .symbols: true
            default: false
            }
            guard current?.character != nil || slides else { continue }
            press.hold?.invalidate()
            highlight(press.id, false)
            press.balloon?.removeFromSuperview()
            press.balloon = nil
            press.id = target.id
            showBalloon(press, target)
            scheduleVariants(press, target)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let press = presses.removeValue(forKey: touch) else { continue }
            finish(press)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let press = presses.removeValue(forKey: touch) else { continue }
            Self.logger.notice("Touch cancelled on \(press.id, privacy: .public)")
            let keepsKey = press.panel == nil && !press.tracking && spec(press.id)?.character != nil
            if !keepsKey {
                press.committed = true
            }
            finish(press, cancelled: !keepsKey)
        }
    }

    private func begin(_ press: Press, _ spec: KeySpec) {
        guard let actions else { return }
        switch spec.kind {
        case .character:
            showBalloon(press, spec)
            scheduleVariants(press, spec)
        case .shift, .symbols:
            highlight(spec.id, true)
            actions.shift()
        case .delete:
            highlight(spec.id, true)
            startDelete()
        case .layer(let target):
            press.fromSwitch = target != .letters
            actions.show(target)
        case .space:
            highlight(spec.id, true)
            press.hold = timer(0.38) { [weak self, weak press] in
                guard let self, let press, self.isActive(press) else { return }
                self.startTracking(press)
            }
        case .emoji, .globe, .enter, .quietGPT:
            highlight(spec.id, true)
        }
    }

    private func finish(_ press: Press, cancelled: Bool = false) {
        press.hold?.invalidate()
        press.balloon?.dismiss()
        highlight(press.id, false)
        if press.origin == .delete {
            stopDelete()
        }
        if press.tracking {
            stopTracking()
            return
        }
        guard let actions else { return }
        if let panel = press.panel {
            panel.removeFromSuperview()
            if !cancelled {
                actions.insert(panel.options[panel.choice])
            }
            return
        }
        guard !cancelled, let spec = spec(press.id) else { return }
        switch spec.kind {
        case .character(let value):
            guard !press.committed else { return }
            actions.insert(value)
            if press.fromSwitch {
                actions.show(.letters)
            }
        case .space: actions.space()
        case .enter: actions.newline()
        case .globe: actions.nextKeyboard()
        case .emoji(let target): actions.show(target)
        case .quietGPT: actions.openPanel()
        default: break
        }
    }

    private func isActive(_ press: Press) -> Bool {
        presses.values.contains { $0 === press }
    }

    private func commitPending() {
        guard let actions else { return }
        for press in presses.values where !press.committed && press.panel == nil {
            guard let value = spec(press.id)?.character else { continue }
            press.hold?.invalidate()
            press.committed = true
            press.balloon?.dismiss()
            press.balloon = nil
            highlight(press.id, false)
            actions.insert(value)
            if press.fromSwitch {
                actions.show(.letters)
            }
        }
    }

    private func showBalloon(_ press: Press, _ spec: KeySpec) {
        guard !isTracking else { return }
        highlight(spec.id, true)
        let balloon = Balloon()
        balloon.show(spec, limit: topLimit, width: bounds.width, style: style)
        addSubview(balloon)
        press.balloon = balloon
    }

    private func scheduleVariants(_ press: Press, _ spec: KeySpec) {
        guard !spec.variants.isEmpty else { return }
        press.hold = timer(0.37) { [weak self, weak press] in
            guard let self, let press, self.isActive(press), !press.committed, press.id == spec.id, let character = spec.character else { return }
            press.balloon?.removeFromSuperview()
            press.balloon = nil
            let panel = VariantsPanel(
                spec: spec,
                options: [character] + spec.variants,
                uppercase: self.uppercase,
                bounds: KeyLayout.margin...(self.bounds.width - KeyLayout.margin),
                top: self.topLimit,
                style: self.style
            )
            self.addSubview(panel)
            press.panel = panel
        }
    }

    private func track(_ press: Press, x: CGFloat) {
        press.latest = x - press.startX
        if !press.tracking, abs(press.latest) > 14 {
            startTracking(press)
        }
        guard press.tracking else { return }
        let steps = Int(((press.latest - press.moved) / 9).rounded(.towardZero))
        if steps != 0 {
            actions?.moveCursor(steps)
            press.moved += CGFloat(steps) * 9
        }
    }

    private func startTracking(_ press: Press) {
        guard !press.tracking else { return }
        press.hold?.invalidate()
        press.tracking = true
        press.moved = press.latest
        isTracking = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        highlight("space", false)
        UIView.animate(withDuration: 0.15) {
            for cap in self.caps.values {
                cap.label.alpha = 0
                cap.icon.alpha = 0
                cap.badge.alpha = 0
            }
        }
    }

    private func stopTracking() {
        isTracking = false
        UIView.animate(withDuration: 0.15) {
            for cap in self.caps.values {
                cap.label.alpha = 1
                cap.icon.alpha = 1
                cap.badge.alpha = 1
            }
        }
    }

    private func startDelete() {
        actions?.deleteBackward()
        deleteCount = 0
        deleteTimer?.invalidate()
        deleteTimer = timer(0.45) { [weak self] in self?.repeatDelete() }
    }

    private func repeatDelete() {
        guard let actions else { return }
        let word = deleteCount >= 18
        if word {
            actions.deleteWord()
        } else {
            actions.deleteBackward()
        }
        deleteCount += 1
        deleteTimer = timer(word ? 0.22 : 0.08) { [weak self] in self?.repeatDelete() }
    }

    private func stopDelete() {
        deleteTimer?.invalidate()
        deleteTimer = nil
    }

    private func timer(_ seconds: TimeInterval, _ block: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in
            MainActor.assumeIsolated { block() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
