import AppKit
import Combine
import JotterCore

/// Search All Notes: replaces the note inside the main window (`WindowServicing.present(inWindow:)`).
/// A rounded search field on top, results as a list or a 3-column card grid, and a floating toolbar with
/// Select, the Ephemeral/Slotted scope and the list/grid switch. ↑/↓ move, Return opens, Esc closes.
@MainActor
final class SearchPane: NSView, NSTextFieldDelegate {
    enum Layout: String { case list, cards }

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
    private let escLabel = NSTextField(labelWithString: "esc")
    private let scroll = NSScrollView()
    private let content = FlippedView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let selectButton = CapsuleButton(symbol: "checkmark.circle", title: "Select")
    private let scopeButton = CapsuleButton(symbol: "wind", title: "Ephemeral")
    private let promoteSelected = CapsuleButton(symbol: "arrow.up.to.line", title: nil)
    private let deleteSelected = CapsuleButton(symbol: "trash", title: nil)
    private let layoutSwitch = LayoutSwitch()

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

    static let sideInset: CGFloat = 12
    static let fieldTop: CGFloat = 30
    static let fieldHeight: CGFloat = 28
    static let toolbarHeight: CGFloat = 30
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
        layoutSwitch.selected = layout == .list ? 0 : 1
        rebuildRows()
    }

    // MARK: Building

    private func build() {
        fieldBox.wantsLayer = true
        fieldBox.layer?.cornerRadius = 8
        glass.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")
        glass.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        escLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        for v in [glass, field, escLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            fieldBox.addSubview(v)
        }

        scroll.documentView = content
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 6, left: 0, bottom: Self.toolbarHeight + 26, right: 0)
        emptyLabel.alignment = .center

        selectButton.action = { [weak self] in self?.toggleSelecting() }
        scopeButton.action = { [weak self] in self?.toggleScope() }
        promoteSelected.action = { [weak self] in self?.promotePicked() }
        promoteSelected.toolTip = "Promote selected to front"
        deleteSelected.action = { [weak self] in self?.deletePicked() }
        deleteSelected.toolTip = "Delete selected"
        promoteSelected.isHidden = true
        deleteSelected.isHidden = true
        layoutSwitch.selected = layoutMode == .list ? 0 : 1
        layoutSwitch.onChange = { [weak self] index in self?.setLayout(index == 0 ? .list : .cards) }

        for v in [scroll, emptyLabel, fieldBox, selectButton, scopeButton, promoteSelected, deleteSelected, layoutSwitch] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        let inset = Self.sideInset
        NSLayoutConstraint.activate([
            fieldBox.topAnchor.constraint(equalTo: topAnchor, constant: Self.fieldTop),
            fieldBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            fieldBox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            fieldBox.heightAnchor.constraint(equalToConstant: Self.fieldHeight),
            glass.leadingAnchor.constraint(equalTo: fieldBox.leadingAnchor, constant: 10),
            glass.centerYAnchor.constraint(equalTo: fieldBox.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: glass.trailingAnchor, constant: 8),
            field.centerYAnchor.constraint(equalTo: fieldBox.centerYAnchor, constant: -1),
            field.trailingAnchor.constraint(equalTo: escLabel.leadingAnchor, constant: -8),
            escLabel.trailingAnchor.constraint(equalTo: fieldBox.trailingAnchor, constant: -12),
            escLabel.centerYAnchor.constraint(equalTo: fieldBox.centerYAnchor),

            scroll.topAnchor.constraint(equalTo: fieldBox.bottomAnchor, constant: 2),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -2 * inset),

            selectButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            selectButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
            scopeButton.leadingAnchor.constraint(equalTo: selectButton.trailingAnchor, constant: 8),
            scopeButton.centerYAnchor.constraint(equalTo: selectButton.centerYAnchor),
            promoteSelected.leadingAnchor.constraint(equalTo: selectButton.trailingAnchor, constant: 8),
            promoteSelected.centerYAnchor.constraint(equalTo: selectButton.centerYAnchor),
            deleteSelected.leadingAnchor.constraint(equalTo: promoteSelected.trailingAnchor, constant: 8),
            deleteSelected.centerYAnchor.constraint(equalTo: selectButton.centerYAnchor),
            layoutSwitch.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            layoutSwitch.centerYAnchor.constraint(equalTo: selectButton.centerYAnchor),
        ])
    }

    private func applyTheme() {
        theme = Theme.current
        let c = Colors(theme)
        layer?.backgroundColor = c.background.cgColor
        fieldBox.layer?.backgroundColor = c.hyperLight.cgColor
        glass.contentTintColor = c.light
        let mono = Typography.font(size: 11)
        field.font = mono
        field.textColor = c.main
        field.placeholderAttributedString = NSAttributedString(string: "Search", attributes: [.font: mono, .foregroundColor: c.light])
        escLabel.font = Typography.font(size: 11)
        escLabel.textColor = c.light
        emptyLabel.font = Typography.font(size: 12)
        emptyLabel.textColor = c.light
        for b in [selectButton, scopeButton, promoteSelected, deleteSelected] { b.apply(c) }
        layoutSwitch.apply(c)
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
        let c = Colors(theme)
        let q = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        views = notes.enumerated().map { i, note in
            let v = SearchResultView(note: note, query: q, layout: layoutMode, colors: c, theme: theme,
                                     meta: SearchModel.meta(modified: note.modified, now: source.now()))
            v.isSelectedRow = showsSelection && i == selected
            v.isPicked = picked.contains(note.id)
            v.onOpen = { [weak self] in self?.clicked(note.id) }
            v.onPromote = note.slot == nil && !note.isArchived ? { [weak self] in self?.promote([note.id]) } : nil
            v.onDelete = { [weak self] in self?.delete([note.id]) }
            content.addSubview(v)
            return v
        }
        if notes.isEmpty, !q.isEmpty, q.lowercased() != SearchModel.archivedQuery {
            let row = SearchResultView(createWith: q, colors: c)
            row.onOpen = { [weak self] in self?.createNote(q) }
            content.addSubview(row)
            createRow = row
        }
        emptyLabel.stringValue = notes.isEmpty && q.isEmpty
            ? (scope == .slotted ? "No slotted notes yet" : "No notes yet") : ""
        emptyLabel.isHidden = emptyLabel.stringValue.isEmpty
        layoutRows()
    }

    override func layout() {
        super.layout()
        layoutRows()
    }

    private func layoutRows() {
        let width = scroll.contentView.bounds.width
        guard width > 0 else { return }
        let inset = Self.sideInset
        var y: CGFloat = 0
        switch layoutMode {
        case .list:
            for v in views + [createRow].compactMap({ $0 }) {
                let h = v.fittingHeight(width: width - 2 * inset)
                v.frame = NSRect(x: inset, y: y, width: width - 2 * inset, height: h)
                y += h + 14
            }
        case .cards:
            let gap: CGFloat = 10, columns: CGFloat = 3
            let w = ((width - 2 * inset - gap * (columns - 1)) / columns).rounded(.down)
            let h = max(132, (w * 0.8).rounded())
            for (i, v) in views.enumerated() {
                let col = CGFloat(i % 3), row = CGFloat(i / 3)
                v.frame = NSRect(x: inset + col * (w + gap), y: row * (h + gap), width: w, height: h)
            }
            y = views.isEmpty ? 0 : CGFloat((views.count + 2) / 3) * (h + gap)
            if let row = createRow {
                let rh = row.fittingHeight(width: width - 2 * inset)
                row.frame = NSRect(x: inset, y: y, width: width - 2 * inset, height: rh)
                y += rh
            }
        }
        content.frame = NSRect(x: 0, y: 0, width: width, height: max(y, 1))
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
        HUD.show(ids.count == 1 ? "Note banished to The Void" : "\(ids.count) notes banished to The Void")
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

    private func toggleSelecting() {
        selecting.toggle()
        picked.removeAll()
        selectButton.set(symbol: selecting ? "checkmark.circle.fill" : "checkmark.circle", title: selecting ? "Done" : "Select")
        scopeButton.isHidden = selecting
        promoteSelected.isHidden = !selecting
        deleteSelected.isHidden = !selecting
        views.forEach { $0.isPicked = false }
    }

    private func toggleScope() {
        scope = scope == .ephemeral ? .slotted : .ephemeral
        scopeButton.set(symbol: scope == .ephemeral ? "wind" : "square.stack.3d.up",
                        title: scope == .ephemeral ? "Ephemeral" : "Slotted")
        selected = 0
        reload()
    }

    func close() { onClose?() }

    // MARK: Keyboard

    func controlTextDidChange(_ obj: Notification) {
        selected = 0
        showsSelection = false
        reload()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let step = layoutMode == .cards ? 3 : 1
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
    let background, main, light, superlight, hyperLight, highlight, reverse: NSColor
    let theme: Theme

    init(_ theme: Theme) {
        self.theme = theme
        background = NSColor(hex: theme.background)
        main = NSColor(hex: theme.typeMain)
        light = NSColor(hex: theme.typeLight)
        superlight = NSColor(hex: theme.typeSuperlight)
        hyperLight = NSColor(hex: theme.typeHyperLight)
        highlight = NSColor(hex: theme.typeHighlight)
        reverse = NSColor(hex: theme.typeReverse)
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

extension Defaults.Keys {
    /// "list" or "cards".
    static let toolsKitSearchLayout = Key<String>("toolsKit.searchLayout", default: "list")
}
