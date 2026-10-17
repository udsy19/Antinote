import AppKit
import SuperNotesCore

/// One Search result: a list row (preview text, meta line, promote/delete buttons on the right) or a card
/// (mini note keeping keyword colours, meta and buttons along the bottom).
@MainActor
final class SearchResultView: NSView {
    let noteID: UUID
    var onOpen: (() -> Void)?
    var onPromote: (() -> Void)? { didSet { promote.isHidden = onPromote == nil } }
    var onDelete: (() -> Void)? { didSet { delete.isHidden = onDelete == nil } }
    var isSelectedRow = false { didSet { updateAppearance() } }
    var isPicked = false { didSet { updateAppearance() } }

    private let layoutMode: SearchPane.Layout
    private let colors: Colors
    private let sizes: SearchPane.Sizes
    private let text = NSTextField(wrappingLabelWithString: "")
    private let meta = NSTextField(labelWithString: "")
    private let promote: SquareIconButton
    private let delete: SquareIconButton
    private var hovered = false { didSet { updateAppearance() } }
    /// List rows: the preview without colours, re-tinted when the row is selected.
    private var listPreview: String?
    private var query = ""

    /// Cards: inner padding, fixed height and corner radius.
    static let cardPadding: CGFloat = 10
    static let cardHeight: CGFloat = 190
    static let cardRadius: CGFloat = 10

    init(note: Note, query: String, layout: SearchPane.Layout, colors: Colors, theme: Theme, sizes: SearchPane.Sizes,
         meta metaText: String) {
        noteID = note.id
        layoutMode = layout
        self.colors = colors
        self.sizes = sizes
        self.query = query
        promote = SquareIconButton(symbol: "arrow.up.to.line", toolTip: "Promote to front", iconSize: sizes.icon)
        delete = SquareIconButton(symbol: "trash", toolTip: "Delete note", iconSize: sizes.icon)
        super.init(frame: .zero)
        configure()
        meta.stringValue = metaText
        if layout == .list {
            listPreview = SearchModel.listPreview(note.content)
            text.maximumNumberOfLines = 3
            meta.font = Typography.font(size: sizes.meta)
        } else {
            text.attributedStringValue = Self.card(note.content, query: query, colors: colors, theme: theme, size: sizes.card)
            text.maximumNumberOfLines = 0
            meta.font = Typography.font(size: sizes.card)
            layer?.cornerRadius = Self.cardRadius
        }
        promote.apply(colors)
        delete.apply(colors)
        promote.onClick = { [weak self] in self?.onPromote?() }
        delete.onClick = { [weak self] in self?.onDelete?() }
        updateAppearance()
    }

    /// The "Create a note starting with …" capsule shown when nothing matches.
    init(createWith query: String, colors: Colors, sizes: SearchPane.Sizes) {
        noteID = UUID()
        layoutMode = .list
        self.colors = colors
        self.sizes = sizes
        promote = SquareIconButton(symbol: "arrow.up.to.line", toolTip: "", iconSize: sizes.icon)
        delete = SquareIconButton(symbol: "trash", toolTip: "", iconSize: sizes.icon)
        super.init(frame: .zero)
        configure()
        let font = Typography.font(size: sizes.text)
        let s = NSMutableAttributedString()
        if let glyph = NSImage(systemSymbolName: "return", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: sizes.text, weight: .regular)) {
            let attachment = NSTextAttachment()
            attachment.image = glyph
            attachment.bounds = NSRect(x: 0, y: font.descender / 2, width: glyph.size.width, height: glyph.size.height)
            s.append(NSAttributedString(attachment: attachment))
            s.append(NSAttributedString(string: "  "))
        }
        s.append(NSAttributedString(string: "Create a note starting with “\(query)”"))
        s.addAttributes([.font: font, .foregroundColor: colors.main], range: NSRange(location: 0, length: s.length))
        text.attributedStringValue = s
        text.maximumNumberOfLines = 1
        text.lineBreakMode = .byTruncatingTail
        meta.isHidden = true
        promote.isHidden = true
        delete.isHidden = true
        isCreateRow = true
        layer?.backgroundColor = colors.hyperLight.cgColor
    }

    private var isCreateRow = false

    /// The natural width of the row's text (the create capsule hugs it).
    var intrinsicWidth: CGFloat { text.attributedStringValue.size().width.rounded(.up) }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func configure() {
        wantsLayer = true
        text.isSelectable = false
        text.lineBreakMode = .byWordWrapping
        text.cell?.truncatesLastVisibleLine = true
        meta.textColor = colors.light.withAlphaComponent(0.5)
        meta.lineBreakMode = .byTruncatingTail
        for v in [text, meta, promote, delete] as [NSView] { addSubview(v) }
    }

    /// List rows: the preview is `typeLight`, or `typeMain` on the keyboard selection; hovered or selected rows get a
    /// faint `typeLight` wash. Cards: `typeHyperLight` with a 1 pt `typeLight` border (2 pt `typeMain` when selected).
    private func updateAppearance() {
        guard !isCreateRow else { return }
        switch layoutMode {
        case .list:
            if let preview = listPreview {
                text.attributedStringValue = Self.highlighted(preview, query: query, size: sizes.text,
                                                              color: isSelectedRow ? colors.main : colors.light, colors: colors)
            }
            let wash = isPicked ? colors.highlight : (hovered || isSelectedRow ? colors.light.withAlphaComponent(0.08) : .clear)
            layer?.backgroundColor = wash.cgColor
        case .cards:
            layer?.backgroundColor = (isPicked ? colors.highlight : colors.hyperLight).cgColor
            layer?.borderWidth = isSelectedRow ? 2 : 1
            layer?.borderColor = (isSelectedRow ? colors.main : colors.light.withAlphaComponent(0.15)).cgColor
        }
    }

    // MARK: Layout

    private var buttonsWidth: CGFloat {
        let side = promote.side
        return promote.isHidden && delete.isHidden ? 0 : (promote.isHidden || delete.isHidden ? side : 2 * side + 6)
    }

    static let listInset: CGFloat = 12

    func fittingHeight(width: CGFloat) -> CGFloat {
        if isCreateRow { return (text.intrinsicContentSize.height + 16).rounded(.up) }
        let p = sizes.rowPadding
        let textWidth = width - 2 * Self.listInset - buttonsWidth - (buttonsWidth > 0 ? 12 : 0)
        let textHeight = text.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: textWidth, height: 1000)).height ?? 16
        return (p + textHeight + 4 + meta.intrinsicContentSize.height + p).rounded(.up)
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        if isCreateRow {
            layer?.cornerRadius = bounds.height / 2
            let h = text.intrinsicContentSize.height
            text.frame = NSRect(x: 14, y: ((bounds.height - h) / 2).rounded(), width: bounds.width - 28, height: h)
            return
        }
        let side = promote.side
        switch layoutMode {
        case .list:
            let p = sizes.rowPadding, inset = Self.listInset
            let textWidth = bounds.width - 2 * inset - buttonsWidth - (buttonsWidth > 0 ? 12 : 0)
            let textHeight = text.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: textWidth, height: 1000)).height ?? 16
            text.frame = NSRect(x: inset, y: p, width: textWidth, height: textHeight)
            meta.frame = NSRect(x: inset, y: p + textHeight + 4, width: textWidth, height: meta.intrinsicContentSize.height)
            let y = ((bounds.height - side) / 2).rounded()
            delete.frame = NSRect(x: bounds.width - inset - side, y: y, width: side, height: side)
            promote.frame = NSRect(x: delete.frame.minX - 6 - side, y: y, width: side, height: side)
        case .cards:
            let pad = Self.cardPadding
            let bottom = bounds.height - pad - side
            delete.frame = NSRect(x: bounds.width - pad - side, y: bottom, width: side, height: side)
            promote.frame = NSRect(x: delete.frame.minX - 6 - side, y: bottom, width: side, height: side)
            let metaHeight = meta.intrinsicContentSize.height
            let metaRight = buttonsWidth > 0 ? (promote.isHidden ? delete.frame.minX : promote.frame.minX) - 4 : bounds.width - pad
            meta.frame = NSRect(x: pad, y: bottom + (side - metaHeight) / 2, width: max(0, metaRight - pad), height: metaHeight)
            text.frame = NSRect(x: pad, y: pad, width: bounds.width - 2 * pad, height: max(0, bottom - 6 - pad))
        }
    }

    // MARK: Events

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

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
    static func highlighted(_ text: String, query: String, size: CGFloat, color: NSColor, colors: Colors) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: Typography.font(size: size), .foregroundColor: color,
        ])
        highlight(query, in: result, colors: colors)
        return result
    }

    /// A miniature note: the first line in bold with its keyword in the keyword colour, list markers removed, line
    /// breaks kept.
    static func card(_ content: String, query: String, colors: Colors, theme: Theme, size: CGFloat) -> NSAttributedString {
        let font = Typography.font(size: size)
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        let lines = content.components(separatedBy: "\n").prefix(16).map(SearchModel.stripMarker)
        let result = NSMutableAttributedString(string: lines.joined(separator: "\n"), attributes: [
            .font: font, .foregroundColor: colors.main,
        ])
        if let first = lines.first {
            result.addAttribute(.font, value: bold, range: NSRange(location: 0, length: (first as NSString).length))
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

/// A promote / delete button: the glyph (medium weight) on a `typeLight` 15 % square with 4 pt corners, 12 pt larger
/// than the glyph.
@MainActor
final class SquareIconButton: NSButton {
    let side: CGFloat
    var onClick: (() -> Void)?

    init(symbol: String, toolTip: String, iconSize: CGFloat) {
        side = iconSize + 12
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)
        symbolConfiguration = .init(pointSize: iconSize, weight: .medium)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        self.toolTip = toolTip
        setAccessibilityLabel(toolTip)
        target = self
        action = #selector(fire)
        wantsLayer = true
        layer?.cornerRadius = 4
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func fire() { onClick?() }

    func apply(_ c: Colors) {
        contentTintColor = c.main
        layer?.backgroundColor = c.light.withAlphaComponent(0.15).cgColor
    }
}

/// A floating capsule holding toolbar items: `typeHyperLight` fill, a 1 pt `typeLight` 20 % border and a soft shadow
/// (black 18 %, radius 8, 2 pt down).
@MainActor
final class ToolbarCapsule: NSView {
    let stack = NSStackView()

    init(horizontalPadding: CGFloat, verticalPadding: CGFloat = 5) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.borderWidth = 1
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        stack.orientation = .horizontal
        stack.spacing = 0
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: verticalPadding),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -verticalPadding),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    func apply(_ c: Colors) {
        layer?.backgroundColor = c.hyperLight.cgColor
        layer?.borderColor = c.light.withAlphaComponent(0.2).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        for case let item as ToolbarItem in stack.arrangedSubviews { item.apply(c) }
        for v in stack.arrangedSubviews where v.identifier == ToolbarCapsule.dividerID {
            v.layer?.backgroundColor = c.light.withAlphaComponent(0.35).cgColor
        }
        for case let label as NSTextField in stack.arrangedSubviews { label.textColor = c.light }
    }

    static let dividerID = NSUserInterfaceItemIdentifier("ToolbarCapsuleDivider")

    /// A 16 pt hairline between groups of items.
    static func divider() -> NSView {
        let v = NSView()
        v.identifier = dividerID
        v.wantsLayer = true
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([v.widthAnchor.constraint(equalToConstant: 1), v.heightAnchor.constraint(equalToConstant: 16)])
        return v
    }
}

/// An item in a toolbar capsule: an SF Symbol and an optional label in the editor monospace, padded 10 × 6 pt. A
/// selected item is a `typeMain` capsule with its glyph in the background colour.
@MainActor
final class ToolbarItem: NSView {
    var action: (() -> Void)?
    var isSelected = false { didSet { if let c = colors { apply(c) } } }
    var isDimmed = false { didSet { if let c = colors { apply(c) } } }
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private var colors: Colors?

    init(symbol: String, title: String?, size: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        icon.symbolConfiguration = .init(pointSize: size, weight: .regular)
        label.font = Typography.font(size: size)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
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

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    func apply(_ c: Colors) {
        colors = c
        let ink = (isSelected ? c.background : c.main).withAlphaComponent(isDimmed ? 0.4 : 1)
        layer?.backgroundColor = (isSelected ? c.main : .clear).cgColor
        icon.contentTintColor = ink
        label.textColor = ink
    }

    override func hitTest(_ point: NSPoint) -> NSView? { isHidden || !frame.contains(point) ? nil : self }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action?() }
    }
}
