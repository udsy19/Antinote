import AppKit
import JotterCore

/// One Search result: a list row (preview text, meta line, promote/delete buttons on the right) or a card
/// (mini note keeping keyword colours, meta and buttons along the bottom).
@MainActor
final class SearchResultView: NSView {
    let noteID: UUID
    var onOpen: (() -> Void)?
    var onPromote: (() -> Void)? { didSet { promote.isHidden = onPromote == nil } }
    var onDelete: (() -> Void)? { didSet { delete.isHidden = onDelete == nil } }
    var isSelectedRow = false { didSet { updateBackground() } }
    var isPicked = false { didSet { updateBackground() } }

    private let layoutMode: SearchPane.Layout
    private let colors: Colors
    private let text = NSTextField(wrappingLabelWithString: "")
    private let meta = NSTextField(labelWithString: "")
    private let promote = SquareIconButton(symbol: "arrow.up.to.line", toolTip: "Promote to front")
    private let delete = SquareIconButton(symbol: "trash", toolTip: "Delete")

    /// Inner padding of list rows (the selection background extends this far around the text).
    static let rowPadding: CGFloat = 6
    static let cardFontSize: CGFloat = 9
    static let listFontSize: CGFloat = 11

    init(note: Note, query: String, layout: SearchPane.Layout, colors: Colors, theme: Theme, meta metaText: String) {
        noteID = note.id
        layoutMode = layout
        self.colors = colors
        super.init(frame: .zero)
        configure()
        meta.stringValue = metaText
        text.attributedStringValue = layout == .list
            ? Self.highlighted(SearchModel.listPreview(note.content), query: query, size: Self.listFontSize, colors: colors)
            : Self.card(note.content, query: query, colors: colors, theme: theme)
        text.maximumNumberOfLines = layout == .list ? 3 : 0
        meta.font = Typography.font(size: layout == .list ? 9 : Self.cardFontSize)
        promote.apply(colors, onCard: layout == .cards)
        delete.apply(colors, onCard: layout == .cards)
        promote.onClick = { [weak self] in self?.onPromote?() }
        delete.onClick = { [weak self] in self?.onDelete?() }
        if layout == .cards {
            layer?.cornerRadius = 10
            layer?.borderWidth = 1
        }
        updateBackground()
    }

    /// The "Create a note starting with …" row shown when nothing matches.
    init(createWith query: String, colors: Colors) {
        noteID = UUID()
        layoutMode = .list
        self.colors = colors
        super.init(frame: .zero)
        configure()
        let font = Typography.font(size: Self.listFontSize)
        let s = NSMutableAttributedString(string: "Create a note starting with ", attributes: [.font: font, .foregroundColor: colors.light])
        s.append(NSAttributedString(string: "“\(query)”", attributes: [.font: font, .foregroundColor: colors.main]))
        text.attributedStringValue = s
        text.maximumNumberOfLines = 2
        meta.stringValue = "Return to create"
        promote.isHidden = true
        delete.isHidden = true
        isSelectedRow = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func configure() {
        wantsLayer = true
        text.isSelectable = false
        text.lineBreakMode = .byWordWrapping
        text.cell?.truncatesLastVisibleLine = true
        meta.font = Typography.font(size: 9)
        meta.textColor = colors.superlight
        meta.lineBreakMode = .byTruncatingTail
        for v in [text, meta, promote, delete] as [NSView] { addSubview(v) }
    }

    private func updateBackground() {
        let fill: NSColor
        if isPicked {
            fill = colors.highlight
        } else if layoutMode == .cards {
            fill = colors.hyperLight
        } else {
            fill = isSelectedRow ? colors.hyperLight.withAlphaComponent(0.6) : .clear
        }
        layer?.backgroundColor = fill.cgColor
        layer?.cornerRadius = layoutMode == .cards ? 10 : 6
        if layoutMode == .cards {
            layer?.borderColor = (isSelectedRow ? colors.light : colors.superlight).cgColor
        }
    }

    // MARK: Layout

    private var buttonsWidth: CGFloat { promote.isHidden && delete.isHidden ? 0 : 2 * SquareIconButton.side + 6 }

    func fittingHeight(width: CGFloat) -> CGFloat {
        let p = Self.rowPadding
        let textWidth = width - 2 * p - buttonsWidth - (buttonsWidth > 0 ? 12 : 0)
        let textHeight = text.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: textWidth, height: 1000)).height ?? 16
        return (p + textHeight + 3 + meta.intrinsicContentSize.height + p).rounded(.up)
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let side = SquareIconButton.side
        switch layoutMode {
        case .list:
            let p = Self.rowPadding
            let textWidth = bounds.width - 2 * p - buttonsWidth - (buttonsWidth > 0 ? 12 : 0)
            let textHeight = text.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: textWidth, height: 1000)).height ?? 16
            text.frame = NSRect(x: p, y: p, width: textWidth, height: textHeight)
            meta.frame = NSRect(x: p, y: p + textHeight + 3, width: textWidth, height: meta.intrinsicContentSize.height)
            let y = ((bounds.height - side) / 2).rounded()
            delete.frame = NSRect(x: bounds.width - p - side, y: y, width: side, height: side)
            promote.frame = NSRect(x: delete.frame.minX - 6 - side, y: y, width: side, height: side)
        case .cards:
            let pad: CGFloat = 9
            let bottom = bounds.height - pad - side
            delete.frame = NSRect(x: bounds.width - pad - side, y: bottom, width: side, height: side)
            promote.frame = NSRect(x: delete.frame.minX - 5 - side, y: bottom, width: side, height: side)
            let metaHeight = meta.intrinsicContentSize.height
            let metaRight = buttonsWidth > 0 ? (promote.isHidden ? delete.frame.minX : promote.frame.minX) - 4 : bounds.width - pad
            var textBottom = bottom - 6
            if meta.attributedStringValue.size().width <= metaRight - pad {
                meta.frame = NSRect(x: pad, y: bottom + (side - metaHeight) / 2, width: max(0, metaRight - pad), height: metaHeight)
            } else {
                // Narrow cards: the date gets its own line above the buttons.
                meta.frame = NSRect(x: pad, y: bottom - 4 - metaHeight, width: bounds.width - 2 * pad, height: metaHeight)
                textBottom = meta.frame.minY - 4
            }
            let top = min(22, (bounds.height * 0.13).rounded())
            text.frame = NSRect(x: pad, y: top, width: bounds.width - 2 * pad, height: max(0, textBottom - top))
        }
    }

    // MARK: Events

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        for b in [promote, delete] where !b.isHidden && b.frame.contains(local) { return b }
        return bounds.contains(local) ? self : nil
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onOpen?() }
    }

    override func mouseDown(with event: NSEvent) {}

    // MARK: Text

    /// `text` in the editor monospace with every occurrence of `query` on a `typeHighlight` background.
    static func highlighted(_ text: String, query: String, size: CGFloat, colors: Colors) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: Typography.font(size: size), .foregroundColor: colors.main,
        ])
        highlight(query, in: result, colors: colors)
        return result
    }

    /// A miniature note: the keyword in its keyword colour, list markers removed, line breaks kept.
    static func card(_ content: String, query: String, colors: Colors, theme: Theme) -> NSAttributedString {
        let font = Typography.font(size: cardFontSize)
        let lines = content.components(separatedBy: "\n").prefix(16).map(SearchModel.stripMarker)
        let result = NSMutableAttributedString(string: lines.joined(separator: "\n"), attributes: [
            .font: font, .foregroundColor: colors.main,
        ])
        if let first = lines.first {
            let detected = NoteMode.detect(firstLine: first)
            if detected.mode != .plain, let r = first.range(of: detected.keyword, options: .caseInsensitive) {
                result.addAttribute(.foregroundColor, value: NSColor(hex: theme.keyword(detected.mode)),
                                    range: NSRange(r, in: first))
            }
        }
        highlight(query, in: result, colors: colors)
        return result
    }

    private static func highlight(_ query: String, in s: NSMutableAttributedString, colors: Colors) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, q.lowercased() != SearchModel.archivedQuery else { return }
        let ns = s.string as NSString
        var from = 0
        while from < ns.length {
            let r = ns.range(of: q, options: [.caseInsensitive, .diacriticInsensitive],
                             range: NSRange(location: from, length: ns.length - from))
            guard r.location != NSNotFound else { break }
            s.addAttribute(.backgroundColor, value: colors.highlight, range: r)
            from = NSMaxRange(r)
        }
    }
}

/// A 22 pt square icon button (promote / delete).
@MainActor
final class SquareIconButton: NSButton {
    static let side: CGFloat = 22
    var onClick: (() -> Void)?

    init(symbol: String, toolTip: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)
        symbolConfiguration = .init(pointSize: 10.5, weight: .medium)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        self.toolTip = toolTip
        setAccessibilityLabel(toolTip)
        target = self
        action = #selector(fire)
        wantsLayer = true
        layer?.cornerRadius = 5
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func fire() { onClick?() }

    func apply(_ c: Colors, onCard: Bool) {
        contentTintColor = c.main
        layer?.backgroundColor = (onCard ? c.superlight.withAlphaComponent(0.55) : c.hyperLight).cgColor
    }
}

/// A floating capsule with an optional icon and label ("✓ Select", "Ephemeral"), `background` fill and a soft
/// shadow.
@MainActor
final class CapsuleButton: NSView {
    var action: (() -> Void)?
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let stack = NSStackView()

    init(symbol: String, title: String?) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = SearchPane.toolbarHeight / 2
        layer?.shadowOpacity = 0.14
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        icon.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        label.font = .systemFont(ofSize: 13)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: SearchPane.toolbarHeight),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: title == nil ? 9 : 13),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: title == nil ? -9 : -15),
        ])
        set(symbol: symbol, title: title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func set(symbol: String, title: String?) {
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title ?? toolTip)
        label.stringValue = title ?? ""
        label.isHidden = title == nil
        setAccessibilityLabel(title ?? toolTip)
    }

    func apply(_ c: Colors) {
        layer?.backgroundColor = c.background.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        icon.contentTintColor = c.main
        label.textColor = c.main
    }

    override func hitTest(_ point: NSPoint) -> NSView? { isHidden || !frame.contains(point) ? nil : self }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action?() }
    }
}

/// The list / grid switch: a capsule with two segments; the selected one has a `typeMain` fill.
@MainActor
final class LayoutSwitch: NSView {
    var selected = 0 { didSet { update() } }
    var onChange: ((Int) -> Void)?
    private let segments = [NSImageView(), NSImageView()]
    private let thumb = NSView()
    private var colors: Colors?
    static let segment = NSSize(width: 34, height: 22)

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = SearchPane.toolbarHeight / 2
        layer?.shadowOpacity = 0.14
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = Self.segment.height / 2
        addSubview(thumb)
        for (i, symbol) in ["list.bullet", "square.grid.2x2"].enumerated() {
            segments[i].image = NSImage(systemSymbolName: symbol, accessibilityDescription: i == 0 ? "List" : "Cards")
            segments[i].symbolConfiguration = .init(pointSize: 11.5, weight: .regular)
            addSubview(segments[i])
        }
        toolTip = "List or cards"
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 2 * Self.segment.width + 8),
            heightAnchor.constraint(equalToConstant: SearchPane.toolbarHeight),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        let y = (bounds.height - Self.segment.height) / 2
        for (i, v) in segments.enumerated() {
            v.frame = NSRect(x: 4 + CGFloat(i) * Self.segment.width, y: y, width: Self.segment.width, height: Self.segment.height)
        }
        thumb.frame = segments[selected].frame
    }

    func apply(_ c: Colors) {
        colors = c
        layer?.backgroundColor = c.background.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        thumb.layer?.backgroundColor = c.main.cgColor
        update()
    }

    private func update() {
        guard let c = colors else { return }
        for (i, v) in segments.enumerated() { v.contentTintColor = i == selected ? c.reverse : c.main }
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = segments.firstIndex(where: { $0.frame.contains(p) }), i != selected else { return }
        selected = i
        onChange?(i)
    }
}
