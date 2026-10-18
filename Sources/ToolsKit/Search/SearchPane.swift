import AppKit
import Combine
import SuperNotesCore

/// Search All Notes: replaces the note inside the main window (`WindowServicing.present(inWindow:)`).
/// A rounded search field on top, results as a list or a grid of cards (columns 230–340 pt wide), and two floating
/// toolbar capsules: Select | Ephemeral/Slotted on the left, list/cards on the right. ↑/↓ move, Return opens, Esc
/// closes.
@MainActor
final class SearchPane: NSView, NSTextFieldDelegate {
    enum Layout: String { case list, cards }

    /// Point sizes for the current text size preset (`SearchMetrics`).
    struct Sizes {
        var text, meta, card, icon, rowPadding: CGFloat

        static var current: Sizes {
            let size = Defaults[.textSize], doubled = Defaults[.doubleFontSize]
            return Sizes(text: SearchMetrics.textSize(size, doubled: doubled), meta: SearchMetrics.metaSize(size, doubled: doubled),
                         card: SearchMetrics.cardTextSize(doubled: doubled), icon: SearchMetrics.iconSize(doubled: doubled),
                         rowPadding: SearchMetrics.rowPadding(size))
        }
    }

    /// The notes Search looks through. Production reads `Services.store`; renders pass fixed notes.
    struct Source {
        var deck: () -> [Note]
        var archived: () -> [Note]
        var now: () -> Date
    }

    var onClose: (() -> Void)?

    private let source: Source
    private let field = NSTextField()
    private let fieldBox = NSView()
    private let glass = NSImageView()
    private let escLabel = EscLabel()
    private let scroll = NSScrollView()
    private let content = FlippedView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var sizes = Sizes.current
    private lazy var selectButton = ToolbarItem(symbol: "checkmark.circle", title: "Select", size: sizes.text)
    private lazy var scopeButton = ToolbarItem(symbol: "wind", title: "Ephemeral", size: sizes.text)
    private let selectDivider = ToolbarCapsule.divider()
    private let pickedLabel = NSTextField(labelWithString: "")
    private lazy var promoteSelected = ToolbarItem(symbol: "arrow.up.to.line", title: nil, size: sizes.text)
    private lazy var deleteSelected = ToolbarItem(symbol: "trash", title: nil, size: sizes.text)
    private lazy var listButton = ToolbarItem(symbol: "list.bullet", title: nil, size: sizes.text)
    private lazy var cardsButton = ToolbarItem(symbol: "square.grid.2x2", title: nil, size: sizes.text)
    private let leftCapsule = ToolbarCapsule(horizontalPadding: 8)
    private let rightCapsule = ToolbarCapsule(horizontalPadding: 6)
    private var fieldHeight: NSLayoutConstraint!
    /// Cards per row in the last layout (↑/↓ move a whole row).
    private var cardColumnCount = 1

    private var theme = Theme.defaultLight
    private var notes: [Note] = []
    private var views: [SearchResultView] = []
    private var createRow: SearchResultView?
    private var selected = 0
    /// The keyboard selection is only drawn once ↑/↓ have been used (Return opens the top result either way).
    private var showsSelection = false
    private var selecting = false
    private var picked: Set<UUID> = []
    private var cancellables: Set<AnyCancellable> = []

    private var layoutMode: Layout {
        get { Layout(rawValue: Defaults[.toolsKitSearchLayout]) ?? .list }
        set { Defaults[.toolsKitSearchLayout] = newValue.rawValue }
    }
    private var scope: SearchScope = .ephemeral

    /// The field: 16 pt from the sides, 38 pt from the top, 12 pt above the results; text inset 16 pt.
    static let sideInset: CGFloat = 16
    static let fieldTop: CGFloat = 38
    static let fieldGap: CGFloat = 12
    /// The toolbar capsules sit 16 pt from the sides and 14 pt from the bottom; results scroll 80 pt clear of them.
    static let toolbarBottom: CGFloat = 14
    static let resultsBottom: CGFloat = 80
    /// Rows built at once; refine the query to reach older notes.
    static let maxResults = 200

    init(source: Source) {
        self.source = source
        super.init(frame: NSRect(x: 0, y: 0, width: 337, height: 386))
        wantsLayer = true
        build()
        applyTheme()
        NotificationCenter.default.publisher(for: Theme.didChange).receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.applyTheme() } }
            .store(in: &cancellables)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Public

    var query: String {
        get { field.stringValue }
        set { field.stringValue = newValue; reload() }
    }

    func focusField() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    /// Re-reads the notes (call when the store changes).
    func reload() {
        let deck = source.deck(), archived = source.archived()
        notes = Array(SearchModel.results(query: field.stringValue, scope: scope, deck: deck, archived: archived)
            .prefix(Self.maxResults))
        picked = picked.intersection(notes.map(\.id))
        selected = min(selected, max(0, notes.count - 1))
        rebuildRows()
    }

    func setLayout(_ layout: Layout) {
        layoutMode = layout
        rebuildRows()
    }

    // MARK: Building

    private func build() {
        fieldBox.wantsLayer = true
        fieldBox.layer?.cornerRadius = 8
        fieldBox.layer?.cornerCurve = .continuous
        glass.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        escLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        escLabel.onClick = { [weak self] in self?.close() }
        for v in [glass, field, escLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            fieldBox.addSubview(v)
        }

        scroll.documentView = content
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        emptyLabel.alignment = .center

        selectButton.action = { [weak self] in self?.toggleSelecting() }
        selectButton.toolTip = "Select multiple notes"
        scopeButton.action = { [weak self] in self?.toggleScope() }
        scopeButton.toolTip = "Show slotted notes instead"
        promoteSelected.action = { [weak self] in self?.promotePicked() }
        promoteSelected.toolTip = "Promote selected to front"
        deleteSelected.action = { [weak self] in self?.deletePicked() }
        deleteSelected.toolTip = "Delete selected"
        listButton.action = { [weak self] in self?.setLayout(.list) }
        listButton.toolTip = "List view"
        cardsButton.action = { [weak self] in self?.setLayout(.cards) }
        cardsButton.toolTip = "Card view"
        for v in [selectButton, selectDivider, scopeButton, pickedLabel, promoteSelected, deleteSelected] as [NSView] {
            leftCapsule.stack.addArrangedSubview(v)
        }
        leftCapsule.stack.setCustomSpacing(8, after: selectDivider)
        leftCapsule.stack.setCustomSpacing(4, after: pickedLabel)
        rightCapsule.stack.addArrangedSubview(listButton)
        rightCapsule.stack.addArrangedSubview(cardsButton)
        for v in [pickedLabel, promoteSelected, deleteSelected] as [NSView] { v.isHidden = true }
        pickedLabel.lineBreakMode = .byTruncatingTail
        pickedLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for v in [scroll, emptyLabel, fieldBox, leftCapsule, rightCapsule] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        let inset = Self.sideInset
        fieldHeight = fieldBox.heightAnchor.constraint(equalToConstant: 30)
        NSLayoutConstraint.activate([fieldHeight] + [
            fieldBox.topAnchor.constraint(equalTo: topAnchor, constant: Self.fieldTop),
            fieldBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            fieldBox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            glass.leadingAnchor.constraint(equalTo: fieldBox.leadingAnchor, constant: inset),
            field.centerYAnchor.constraint(equalTo: fieldBox.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: glass.trailingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: escLabel.leadingAnchor, constant: -8),
            glass.centerYAnchor.constraint(equalTo: fieldBox.centerYAnchor),
            escLabel.trailingAnchor.constraint(equalTo: fieldBox.trailingAnchor, constant: -inset),
            escLabel.centerYAnchor.constraint(equalTo: fieldBox.centerYAnchor),

            scroll.topAnchor.constraint(equalTo: fieldBox.bottomAnchor, constant: Self.fieldGap),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -2 * inset),

            leftCapsule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            leftCapsule.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.toolbarBottom),
            rightCapsule.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            leftCapsule.trailingAnchor.constraint(lessThanOrEqualTo: rightCapsule.leadingAnchor, constant: -8),
            rightCapsule.centerYAnchor.constraint(equalTo: leftCapsule.centerYAnchor),
        ])
    }

    /// The field: `typeHyperLight` rounded rectangle; the magnifier, placeholder (70 %) and "esc" (40 %) in `typeLight`,
    /// the query in `typeMain`, all at the Search text size.
    private func applyTheme() {
        theme = Theme.current
        sizes = Sizes.current
        let c = Colors(theme)
        layer?.backgroundColor = c.background.cgColor
        fieldBox.layer?.backgroundColor = c.hyperLight.cgColor
        glass.symbolConfiguration = .init(pointSize: sizes.text, weight: .regular)
        glass.contentTintColor = c.light
        let mono = Typography.font(size: sizes.text)
        field.font = mono
        field.textColor = c.main
        field.placeholderAttributedString = NSAttributedString(string: "Search", attributes: [
            .font: mono, .foregroundColor: c.light.withAlphaComponent(0.7),
        ])
        // Field height: one line of text plus the size-dependent padding above and below.
        fieldHeight.constant = ceil(mono.ascender - mono.descender + mono.leading) + 2 * sizes.rowPadding
        escLabel.font = mono
        escLabel.textColor = c.light.withAlphaComponent(0.4)
        emptyLabel.font = Typography.font(size: sizes.text)
        emptyLabel.textColor = c.light.withAlphaComponent(0.5)
        pickedLabel.font = Typography.font(size: sizes.text)
        leftCapsule.apply(c)
        rightCapsule.apply(c)
        rebuildRows()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme()
    }

    // MARK: Rows

    private func rebuildRows() {
        views.forEach { $0.removeFromSuperview() }
        createRow?.removeFromSuperview()
        createRow = nil
        listButton.isSelected = layoutMode == .list
        cardsButton.isSelected = layoutMode == .cards
        let c = Colors(theme)
        let q = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        views = notes.enumerated().map { i, note in
            let v = SearchResultView(note: note, query: q, layout: layoutMode, colors: c, theme: theme, sizes: sizes,
                                     meta: SearchModel.meta(modified: note.modified, now: source.now()))
            v.isSelectedRow = showsSelection && i == selected
            v.isPicked = picked.contains(note.id)
            v.onOpen = { [weak self] in self?.clicked(note.id) }
            v.onPromote = note.slot == nil && !note.isArchived ? { [weak self] in self?.promote([note.id]) } : nil
            v.onDelete = { [weak self] in self?.delete([note.id]) }
            content.addSubview(v)
            return v
        }
        if notes.isEmpty, !q.isEmpty, q.lowercased() != SearchModel.archivedQuery, scope == .ephemeral {
            let row = SearchResultView(createWith: q, colors: c, sizes: sizes)
            row.onOpen = { [weak self] in self?.createNote(q) }
            content.addSubview(row)
            createRow = row
        }
        emptyLabel.stringValue = !notes.isEmpty || createRow != nil ? ""
            : !q.isEmpty ? "Nothing found" : (scope == .slotted ? "No slotted notes yet" : "No notes yet")
        emptyLabel.isHidden = emptyLabel.stringValue.isEmpty
        layoutRows()
    }

    override func layout() {
        super.layout()
        layoutRows()
    }

    /// List: full-width rows (4 pt in from the sides, 8 pt below the field). Cards: 190 pt cards in columns of
    /// 230–340 pt, 12 pt apart and 16 pt in from the sides; the grid is centred when columns hit their maximum.
    private func layoutRows() {
        let width = scroll.contentView.bounds.width
        guard width > 0 else { return }
        var y: CGFloat
        switch layoutMode {
        case .list:
            let inset: CGFloat = 4
            y = 8
            for v in views {
                let h = v.fittingHeight(width: width - 2 * inset)
                v.frame = NSRect(x: inset, y: y, width: width - 2 * inset, height: h)
                y += h
            }
        case .cards:
            let inset = Self.sideInset, gap: CGFloat = 12
            let columns = SearchMetrics.cardColumns(width: width - 2 * inset)
            cardColumnCount = columns.count
            let gridWidth = CGFloat(columns.count) * columns.width + CGFloat(columns.count - 1) * gap
            let left = inset + ((width - 2 * inset - gridWidth) / 2).rounded(.down)
            let h = SearchResultView.cardHeight
            y = 12
            for (i, v) in views.enumerated() {
                let col = CGFloat(i % columns.count), row = CGFloat(i / columns.count)
                v.frame = NSRect(x: left + col * (columns.width + gap), y: y + row * (h + gap), width: columns.width, height: h)
            }
            if !views.isEmpty { y += CGFloat((views.count + columns.count - 1) / columns.count) * (h + gap) - gap }
        }
        if let row = createRow {
            let rh = row.fittingHeight(width: width)
            let rw = min(width - 2 * Self.sideInset, row.intrinsicWidth + 28)
            row.frame = NSRect(x: ((width - rw) / 2).rounded(), y: y + 8, width: rw, height: rh)
            y += rh + 8
        }
        content.frame = NSRect(x: 0, y: 0, width: width, height: max(y + Self.resultsBottom, 1))
    }

    private func scrollSelectedIntoView() {
        guard views.indices.contains(selected) else { return }
        content.scrollToVisible(views[selected].frame.insetBy(dx: 0, dy: -8))
    }

    private func moveSelection(_ delta: Int) {
        guard !views.isEmpty else { return }
        views[selected].isSelectedRow = false
        if showsSelection { selected = min(max(0, selected + delta), views.count - 1) }
        showsSelection = true
        views[selected].isSelectedRow = true
        scrollSelectedIntoView()
    }

    // MARK: Actions

    private func clicked(_ id: UUID) {
        guard selecting else { return open(id) }
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
        views.first { $0.noteID == id }?.isPicked = picked.contains(id)
        pickedLabel.stringValue = "\(picked.count) selected"
    }

    private func open(_ id: UUID) {
        close()
        Services.windows?.show(noteID: id)
    }

    private func createNote(_ text: String) {
        guard Services.store != nil else { return }
        let note = Services.store.create(content: text)
        open(note.id)
    }

    private func promote(_ ids: [UUID]) {
        guard Services.store != nil, !ids.isEmpty else { return }
        for id in ids.reversed() { Services.store.promoteToFront(id) }
        HUD.show(ids.count == 1 ? "Promoted note to front" : "Promoted \(ids.count) notes to front", kind: .success)
        reload()
    }

    private func delete(_ ids: [UUID]) {
        guard Services.store != nil, !ids.isEmpty else { return }
        for id in ids { Services.store.moveToVoid(id) }
        HUD.show(ids.count == 1 ? "Note deleted" : "\(ids.count) notes deleted")
        reload()
    }

    private func promotePicked() {
        promote(notes.filter { picked.contains($0.id) && $0.slot == nil && !$0.isArchived }.map(\.id))
        toggleSelecting()
    }

    private func deletePicked() {
        delete(notes.filter { picked.contains($0.id) }.map(\.id))
        toggleSelecting()
    }

    /// Select mode: the Select item turns solid and the scope switch gives way to "N selected" plus promote/delete.
    private func toggleSelecting() {
        selecting.toggle()
        picked.removeAll()
        selectButton.set(symbol: selecting ? "checkmark.circle.fill" : "checkmark.circle", title: "Select")
        selectButton.isSelected = selecting
        scopeButton.isHidden = selecting
        pickedLabel.stringValue = "0 selected"
        for v in [pickedLabel, promoteSelected, deleteSelected] as [NSView] { v.isHidden = !selecting }
        views.forEach { $0.isPicked = false }
    }

    private func toggleScope() {
        scope = scope == .ephemeral ? .slotted : .ephemeral
        scopeButton.set(symbol: scope == .ephemeral ? "wind" : "square.grid.3x3.fill",
                        title: scope == .ephemeral ? "Ephemeral" : "Slotted")
        scopeButton.toolTip = scope == .ephemeral ? "Show slotted notes instead" : "Show ephemeral notes instead"
        selectButton.isDimmed = scope == .slotted
        selected = 0
        reload()
    }

    /// Turns Select mode on with `ids` picked.
    func select(_ ids: [UUID]) {
        if !selecting { toggleSelecting() }
        ids.forEach(clicked)
    }

    func close() { onClose?() }

    // MARK: Keyboard

    func controlTextDidChange(_ obj: Notification) {
        selected = 0
        showsSelection = false
        reload()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let step = layoutMode == .cards ? cardColumnCount : 1
        switch selector {
        case #selector(NSResponder.moveUp(_:)): moveSelection(-step)
        case #selector(NSResponder.moveDown(_:)): moveSelection(step)
        case #selector(NSResponder.insertNewline(_:)):
            if views.indices.contains(selected) { open(views[selected].noteID) } else { createRow?.onOpen?() }
        case #selector(NSResponder.cancelOperation(_:)): close()
        default: return false
        }
        return true
    }

    override func cancelOperation(_ sender: Any?) { close() }
}

/// Theme colours used by the Search views.
struct Colors {
    let background, main, light, hyperLight, highlight: NSColor
    let theme: Theme

    init(_ theme: Theme) {
        self.theme = theme
        background = NSColor(hex: theme.background)
        main = NSColor(hex: theme.typeMain)
        light = NSColor(hex: theme.typeLight)
        hyperLight = NSColor(hex: theme.typeHyperLight)
        highlight = NSColor(hex: theme.typeHighlight)
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The "esc" hint at the end of the field; clicking it closes Search.
final class EscLabel: NSTextField {
    var onClick: (() -> Void)?

    init() {
        super.init(frame: .zero)
        stringValue = "esc"
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

extension Defaults.Keys {
    /// "list" or "cards".
    static let toolsKitSearchLayout = Key<String>("toolsKit.searchLayout", default: "list")
}
