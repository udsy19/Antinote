import AppKit
import JotterCore

/// A floating search field over a result list: ↑/↓ select, Enter runs, Esc or clicking elsewhere closes.
/// Used by the command palette and Search All Notes.
@MainActor
final class QuickPanel: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    struct Row {
        var title: NSAttributedString
        var detail: NSAttributedString?
        var symbol: String?
        /// Right-aligned hint, e.g. a keyboard shortcut or "Slot 2".
        var trailing: String?
        var action: () -> Void
    }

    private let panel: KeyPanel
    private let field = NSTextField()
    private let table = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let emptyText: String
    private let provider: (String) -> [Row]
    private var rows: [Row] = []

    init(placeholder: String, emptyText: String, provider: @escaping (String) -> [Row]) {
        self.provider = provider
        self.emptyText = emptyText
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onEscape = { [weak self] in self?.close() }
        panel.onResignKey = { [weak self] in self?.close() }
        buildViews(placeholder: placeholder)
    }

    var isVisible: Bool { panel.isVisible }

    func show(query: String = "") {
        field.stringValue = query
        reload()
        let screen = NSScreen.active.visibleFrame
        panel.setFrameOrigin(NSPoint(x: screen.midX - panel.frame.width / 2,
                                     y: screen.maxY - screen.height * 0.22 - panel.frame.height))
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    func reload() {
        rows = provider(field.stringValue)
        table.reloadData()
        if !rows.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false); table.scrollRowToVisible(0) }
        emptyLabel.stringValue = rows.isEmpty && !field.stringValue.isEmpty ? emptyText : ""
    }

    private func activate(_ row: Int) {
        guard rows.indices.contains(row) else { return }
        let action = rows[row].action
        close()
        action()
    }

    // MARK: Layout

    private func buildViews(placeholder: String) {
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true

        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 20)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.cell?.isScrollable = true

        let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 17, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor

        let column = NSTableColumn(identifier: .init("row"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 42
        table.style = .inset
        table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(doubleClicked)
        table.refusesFirstResponder = true

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        let separator = NSBox()
        separator.boxType = .separator

        for v in [icon, field, separator, scroll, emptyLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(v)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -18),
            field.topAnchor.constraint(equalTo: background.topAnchor, constant: 16),
            separator.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 14),
            separator.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -6),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
        panel.contentView = background
    }

    // MARK: Keyboard

    func controlTextDidChange(_ obj: Notification) { reload() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): moveSelection(-1)
        case #selector(NSResponder.moveDown(_:)): moveSelection(1)
        case #selector(NSResponder.insertNewline(_:)): activate(table.selectedRow)
        case #selector(NSResponder.cancelOperation(_:)): close()
        default: return false
        }
        return true
    }

    private func moveSelection(_ delta: Int) {
        guard !rows.isEmpty else { return }
        let row = min(max(0, table.selectedRow + delta), rows.count - 1)
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    @objc private func doubleClicked() { activate(table.clickedRow) }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("QuickPanelRow")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? RowView ?? RowView(identifier: id)
        cell.configure(rows[row])
        return cell
    }

    private final class RowView: NSTableCellView {
        private let icon = NSImageView()
        private let title = NSTextField(labelWithString: "")
        private let detail = NSTextField(labelWithString: "")
        private let trailing = NSTextField(labelWithString: "")

        init(identifier: NSUserInterfaceItemIdentifier) {
            super.init(frame: .zero)
            self.identifier = identifier
            icon.symbolConfiguration = .init(pointSize: 14, weight: .regular)
            icon.contentTintColor = .secondaryLabelColor
            title.lineBreakMode = .byTruncatingTail
            detail.lineBreakMode = .byTruncatingTail
            detail.textColor = .secondaryLabelColor
            detail.font = .systemFont(ofSize: 11)
            trailing.textColor = .tertiaryLabelColor
            trailing.font = .systemFont(ofSize: 11)
            trailing.setContentCompressionResistancePriority(.required, for: .horizontal)
            let texts = NSStackView(views: [title, detail])
            texts.orientation = .vertical
            texts.alignment = .leading
            texts.spacing = 1
            let stack = NSStackView(views: [icon, texts, trailing])
            stack.spacing = 10
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: 20),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        required init?(coder: NSCoder) { nil }

        func configure(_ row: Row) {
            icon.image = row.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            title.attributedStringValue = row.title
            detail.attributedStringValue = row.detail ?? NSAttributedString()
            detail.isHidden = row.detail == nil
            trailing.stringValue = row.trailing ?? ""
        }
    }
}

extension NSAttributedString {
    /// `text` with the characters at `offsets` (fuzzy match) in bold.
    static func highlighting(_ text: String, offsets: [Int], size: CGFloat = 13) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size)])
        let chars = Array(text)
        for offset in offsets where offset < chars.count {
            let start = text.index(text.startIndex, offsetBy: offset)
            result.addAttributes([.font: NSFont.systemFont(ofSize: size, weight: .bold)],
                                 range: NSRange(start..<text.index(after: start), in: text))
        }
        return result
    }

    /// `text` with `ranges` highlighted in the accent colour.
    static func highlighting(_ text: String, ranges: [Range<String.Index>], size: CGFloat = 11) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.secondaryLabelColor,
        ])
        for range in ranges {
            result.addAttributes([.font: NSFont.systemFont(ofSize: size, weight: .semibold),
                                  .foregroundColor: NSColor.labelColor,
                                  .backgroundColor: NSColor.findHighlightColor.withAlphaComponent(0.45)],
                                 range: NSRange(range, in: text))
        }
        return result
    }
}
