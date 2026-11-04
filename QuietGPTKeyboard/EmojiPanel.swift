import UIKit

final class EmojiCell: UICollectionViewCell {
    let label = UILabel()
    var lit = UIColor.clear

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        contentView.addSubview(label)
        contentView.layer.cornerRadius = KeyStyle.radius
        contentView.layer.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) { nil }

    override var isHighlighted: Bool {
        didSet { contentView.backgroundColor = isHighlighted ? lit : .clear }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
    }
}

final class EmojiPanel: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private struct Item {
        let text: String
        let tones: [String]
    }

    private struct Section {
        let title: String
        let symbol: String
        var items: [Item]
    }

    private static let recentsKey = "emojiRecents"
    private static let recentsLimit = 40
    private static let starters = ["😀", "😂", "🥰", "😊", "😭", "🙏", "👍", "❤️", "🔥", "✨", "🎉", "😘"]
    private static let rows: CGFloat = 5
    private static let columns: CGFloat = 8.5
    private static let titleHeight: CGFloat = 26
    private static let inset: CGFloat = 6
    private static let dot: CGFloat = 30

    private static let catalog: [Section] = EmojiData.sections.map { section in
        Section(
            title: section.title,
            symbol: section.symbol,
            items: section.text.split(separator: " ").map { entry in
                let parts = entry.split(separator: "|").map(String.init)
                return Item(text: parts[0], tones: Array(parts.dropFirst()))
            }
        )
    }

    private static let tones: [String: [String]] = {
        var map: [String: [String]] = [:]
        for section in catalog {
            for item in section.items where !item.tones.isEmpty {
                map[item.text] = item.tones
            }
        }
        return map
    }()

    var onInsert: (String) -> Void = { _ in }
    var gridHeight: CGFloat = 0 {
        didSet { if gridHeight != oldValue { setNeedsLayout() } }
    }
    var barFrame = CGRect.zero {
        didSet { if barFrame != oldValue { setNeedsLayout() } }
    }

    private let flow = UICollectionViewFlowLayout()
    private lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: flow)
    private let titleLabel = UILabel()
    private let bar = UIStackView()
    private let indicator = UIView()
    private var buttons: [UIButton] = []
    private var sections: [Section] = []
    private var starts: [CGFloat] = []
    private var current = 0
    private var fontSize: CGFloat = 32
    private var variants: VariantsPanel?
    private var held: IndexPath?

    private var style: KeyStyle { .current(traitCollection) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 1, alpha: 0.001)
        sections = [recents()] + Self.catalog

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        addSubview(titleLabel)

        flow.scrollDirection = .horizontal
        flow.minimumLineSpacing = 0
        flow.minimumInteritemSpacing = 0
        flow.sectionInset = UIEdgeInsets(top: 0, left: Self.inset, bottom: 0, right: Self.inset)
        grid.backgroundColor = .clear
        grid.showsHorizontalScrollIndicator = false
        grid.alwaysBounceHorizontal = true
        grid.delaysContentTouches = false
        grid.dataSource = self
        grid.delegate = self
        grid.register(EmojiCell.self, forCellWithReuseIdentifier: "emoji")
        addSubview(grid)

        let hold = UILongPressGestureRecognizer(target: self, action: #selector(hold(_:)))
        hold.minimumPressDuration = 0.37
        grid.addGestureRecognizer(hold)

        indicator.layer.cornerRadius = Self.dot / 2
        addSubview(indicator)

        bar.axis = .horizontal
        bar.distribution = .fillEqually
        addSubview(bar)
        for (index, section) in sections.enumerated() {
            let button = UIButton(type: .custom)
            button.setImage(UIImage(systemName: section.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)), for: .normal)
            button.tag = index
            button.accessibilityLabel = name(section)
            button.addTarget(self, action: #selector(choose(_:)), for: .touchUpInside)
            bar.addArrangedSubview(button)
            buttons.append(button)
        }

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: EmojiPanel, _: UITraitCollection) in
            view.applyStyle()
            view.grid.reloadData()
        }
        applyStyle()
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        titleLabel.frame = CGRect(x: 12, y: 6, width: bounds.width - 24, height: 18)
        let frame = CGRect(x: 0, y: Self.titleHeight, width: bounds.width, height: max(gridHeight - Self.titleHeight, 0))
        let height = (frame.height / Self.rows).rounded(.down)
        let size = CGSize(width: (bounds.width / Self.columns).rounded(.down), height: height)
        if grid.frame != frame || flow.itemSize != size, height > 0 {
            grid.frame = frame
            flow.itemSize = size
            fontSize = min(height * 0.86, 33)
            flow.invalidateLayout()
            grid.reloadData()
            grid.layoutIfNeeded()
            measure()
        }
        bar.frame = barFrame
        bar.layoutIfNeeded()
        moveIndicator()
    }

    func refresh() {
        sections[0] = recents()
        grid.reloadData()
        grid.layoutIfNeeded()
        measure()
        update(section())
    }

    private func applyStyle() {
        let style = style
        titleLabel.textColor = style.secondary
        indicator.backgroundColor = style.key
        update(current, force: true)
    }

    private func name(_ section: Section) -> String {
        KeyboardText.string(String.LocalizationValue(section.title))
    }

    private func recents() -> Section {
        let saved = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? Self.starters
        return Section(
            title: "Frequently Used",
            symbol: "clock",
            items: saved.map { Item(text: $0, tones: Self.tones[$0] ?? []) }
        )
    }

    private func remember(_ text: String) {
        var saved = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? Self.starters
        saved.removeAll { $0 == text }
        saved.insert(text, at: 0)
        UserDefaults.standard.set(Array(saved.prefix(Self.recentsLimit)), forKey: Self.recentsKey)
    }

    private func insert(_ text: String) {
        UIDevice.current.playInputClick()
        remember(text)
        onInsert(text)
    }

    private func measure() {
        starts = sections.indices.map { index in
            guard !sections[index].items.isEmpty,
                  let frame = grid.layoutAttributesForItem(at: IndexPath(item: 0, section: index))?.frame else { return 0 }
            return frame.minX - Self.inset
        }
    }

    private func section() -> Int {
        let offset = grid.contentOffset.x + 1
        return starts.lastIndex { $0 <= offset } ?? 0
    }

    private func update(_ index: Int, force: Bool = false) {
        guard force || index != current else { return }
        current = index
        titleLabel.text = name(sections[index]).uppercased()
        let style = style
        for (position, button) in buttons.enumerated() {
            button.tintColor = position == index ? style.text : style.secondary
            button.accessibilityTraits = position == index ? [.button, .selected] : .button
        }
        moveIndicator()
    }

    private func moveIndicator() {
        guard buttons.indices.contains(current) else { return }
        let side = min(Self.dot, barFrame.height)
        indicator.layer.cornerRadius = side / 2
        indicator.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        indicator.center = bar.convert(buttons[current].center, to: self)
    }

    @objc private func choose(_ sender: UIButton) {
        UIDevice.current.playInputClick()
        guard starts.indices.contains(sender.tag) else { return }
        let limit = max(grid.contentSize.width - grid.bounds.width, 0)
        grid.setContentOffset(CGPoint(x: min(starts[sender.tag], limit), y: 0), animated: false)
        update(sender.tag)
    }

    @objc private func hold(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard let path = grid.indexPathForItem(at: gesture.location(in: grid)) else { return }
            held = path
            let item = sections[path.section].items[path.item]
            guard !item.tones.isEmpty, let cell = grid.cellForItem(at: path) else { return }
            let face = cell.convert(cell.bounds, to: self)
            let spec = KeySpec(id: "emoji", kind: .character(item.text), face: face, opensLeft: face.midX > bounds.midX, label: item.text)
            let panel = VariantsPanel(
                spec: spec,
                options: [item.text] + item.tones,
                uppercase: false,
                bounds: KeyLayout.margin...(bounds.width - KeyLayout.margin),
                top: 0,
                style: style
            )
            addSubview(panel)
            variants = panel
        case .changed:
            variants?.track(x: gesture.location(in: self).x)
        case .ended:
            if let variants {
                insert(variants.options[variants.choice])
            } else if let held {
                insert(sections[held.section].items[held.item].text)
            }
            finishHold()
        default:
            finishHold()
        }
    }

    private func finishHold() {
        variants?.removeFromSuperview()
        variants = nil
        held = nil
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "emoji", for: indexPath) as! EmojiCell
        cell.label.text = sections[indexPath.section].items[indexPath.item].text
        cell.label.font = .systemFont(ofSize: fontSize)
        cell.lit = style.lit
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        insert(sections[indexPath.section].items[indexPath.item].text)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        update(section())
    }
}
