import AppKit
import SuperNotesCore

/// The find and replace shelf docked under the note (⇧⌘F): a disclosure chevron that shows the Replace row, the
/// search field with an "Aa" (match case) toggle and a match-type popup (Contains, Matches Word, Starts With, Ends
/// With, Regex), ‹ › to step through matches and Done; the second row holds the Replace field and Replace | All.
/// The shelf sits on `backgroundFade` under a hairline; the controls are the system's own.
final class FindShelf: NSView, NSTextFieldDelegate {
    static let rowHeight: CGFloat = 28
    static let padding: CGFloat = 8
    /// The shelf's height with or without its Replace row.
    static func height(expanded: Bool) -> CGFloat { padding * 2 + rowHeight * (expanded ? 2 : 1) + (expanded ? 6 : 0) }

    var onSearch: (() -> Void)?
    var onNext: ((_ backwards: Bool) -> Void)?
    var onReplace: (() -> Void)?
    var onReplaceAll: (() -> Void)?
    var onClose: (() -> Void)?
    /// The Replace row was shown or hidden (the shelf's height changes).
    var onResize: (() -> Void)?

    private let chevron = NSButton()
    private let field = NSTextField()
    private let matchCase = NSButton(title: "Aa", target: nil, action: nil)
    private let matchType = NSPopUpButton(frame: .zero, pullsDown: false)
    private let navigation = NSSegmentedControl()
    private let done = NSButton(title: "Done", target: nil, action: nil)
    private let replaceField = NSTextField()
    private let replaceButtons = NSSegmentedControl()
    private let replaceRow: NSStackView
    private var theme: Theme = .defaultLight

    private(set) var isExpanded = false
    var term: String { field.stringValue }
    var replacement: String { replaceField.stringValue }
    var options: EditorLogic.Find.Options {
        EditorLogic.Find.Options(matchCase: matchCase.state == .on,
                                 type: EditorLogic.Find.MatchType.allCases[max(0, matchType.indexOfSelectedItem)])
    }

    override init(frame: NSRect) {
        replaceRow = NSStackView()
        super.init(frame: frame)
        wantsLayer = true

        chevron.bezelStyle = .accessoryBarAction
        chevron.isBordered = false
        chevron.imagePosition = .imageOnly
        chevron.target = self
        chevron.action = #selector(toggleReplace)
        chevron.toolTip = "Show Replace"

        field.placeholderString = "Find"
        field.bezelStyle = .roundedBezel
        field.delegate = self
        field.cell?.isScrollable = true
        field.lineBreakMode = .byClipping

        matchCase.setButtonType(.pushOnPushOff)
        matchCase.bezelStyle = .accessoryBarAction
        matchCase.toolTip = "Match Case"
        matchCase.target = self
        matchCase.action = #selector(optionsChanged)

        matchType.addItems(withTitles: EditorLogic.Find.MatchType.allCases.map(\.title))
        matchType.isBordered = false
        matchType.controlSize = .regular
        matchType.target = self
        matchType.action = #selector(optionsChanged)

        navigation.segmentCount = 2
        navigation.trackingMode = .momentary
        navigation.setImage(NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous"), forSegment: 0)
        navigation.setImage(NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next"), forSegment: 1)
        navigation.setToolTip("Previous Match", forSegment: 0)
        navigation.setToolTip("Next Match", forSegment: 1)
        navigation.target = self
        navigation.action = #selector(navigate)

        done.bezelStyle = .push
        done.target = self
        done.action = #selector(close)

        replaceField.placeholderString = "Replace"
        replaceField.bezelStyle = .roundedBezel
        replaceField.delegate = self
        replaceField.cell?.isScrollable = true

        replaceButtons.segmentCount = 2
        replaceButtons.trackingMode = .momentary
        replaceButtons.setLabel("Replace", forSegment: 0)
        replaceButtons.setLabel("All", forSegment: 1)
        replaceButtons.setToolTip("Replace this match and find the next one", forSegment: 0)
        replaceButtons.setToolTip("Replace every match", forSegment: 1)
        replaceButtons.target = self
        replaceButtons.action = #selector(replaceClicked)

        // The match options sit inside the right end of the search box.
        let searchBox = NSStackView(views: [field, matchCase, matchType])
        searchBox.spacing = 2
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let findRow = NSStackView(views: [chevron, searchBox, navigation, done])
        findRow.spacing = 6
        replaceRow.setViews([replaceField, replaceButtons], in: .leading)
        replaceRow.spacing = 6
        replaceField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let rows = NSStackView(views: [findRow, replaceRow])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        for row in [findRow, replaceRow] { row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.padding),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.padding),
            rows.topAnchor.constraint(equalTo: topAnchor, constant: Self.padding),
            chevron.widthAnchor.constraint(equalToConstant: 20),
            findRow.heightAnchor.constraint(equalToConstant: Self.rowHeight),
            replaceRow.heightAnchor.constraint(equalToConstant: Self.rowHeight),
            // Replace | All lines up under ‹ › Done.
            replaceButtons.trailingAnchor.constraint(equalTo: done.trailingAnchor),
            replaceButtons.leadingAnchor.constraint(equalTo: navigation.leadingAnchor),
        ])
        setExpanded(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the Replace row or not.
    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        replaceRow.isHidden = !expanded
        chevron.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        chevron.toolTip = expanded ? "Hide Replace" : "Show Replace"
        onResize?()
    }

    /// Puts `term` in the search field (when given) and focuses it with its text selected.
    func focus(term: String? = nil) {
        if let term { field.stringValue = term }
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    /// The field turns red-tinted when its term finds nothing.
    func showFound(_ found: Bool) {
        field.textColor = found ? .labelColor : .systemRed
    }

    func apply(theme: Theme) {
        self.theme = theme
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(hex: theme.backgroundFade).setFill()
        bounds.fill()
        NSColor(hex: theme.typeSuperlight).setFill()
        NSRect(x: 0, y: isFlipped ? 0 : bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    // MARK: Actions

    @objc private func toggleReplace() { setExpanded(!isExpanded) }
    @objc private func optionsChanged() { onSearch?() }
    @objc private func navigate() { onNext?(navigation.selectedSegment == 0) }
    @objc private func close() { onClose?() }
    @objc private func replaceClicked() {
        if replaceButtons.selectedSegment == 0 { onReplace?() } else { onReplaceAll?() }
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSTextField) === field { onSearch?() }
    }

    /// Return finds the next match (⇧Return the previous; Return in Replace replaces); Esc closes.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if control === replaceField { onReplace?() } else {
                onNext?(NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
            }
        case #selector(NSResponder.cancelOperation(_:)): onClose?()
        default: return false
        }
        return true
    }
}
