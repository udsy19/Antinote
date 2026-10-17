import AppKit
import UniformTypeIdentifiers
import Vision
import JotterCore

// MARK: - OCR

/// Image → text with Vision ("Drop an image to capture text.").
enum OCR {
    static func hasImage(_ pb: NSPasteboard) -> Bool { image(from: pb) != nil }

    static func image(from pb: NSPasteboard) -> CGImage? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingContentsConformToTypes: [UTType.image.identifier]]
        if let url = (pb.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first,
           let image = NSImage(contentsOf: url) {
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        guard pb.availableType(from: [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")]) != nil,
              let image = NSImage(pasteboard: pb) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Recognises text off the main thread; `completion` runs on the main thread with nil on failure.
    static func recognize(_ image: CGImage, completion: @escaping @MainActor (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            var text: String?
            if (try? handler.perform([request])) != nil {
                text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }
            DispatchQueue.main.async { completion(text) }
        }
    }
}

// MARK: - AutoPaste

/// Polls the pasteboard every 0.4 s and reports each newly copied string.
@MainActor
final class AutoPasteMonitor {
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private(set) var count = 0
    var isRunning: Bool { timer != nil }
    var onNewString: ((String) -> Void)?

    func start() {
        stop()
        count = 0
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// Ignore a pasteboard write made by the editor itself (copy/cut).
    func ignoreCurrentContents() { lastChangeCount = NSPasteboard.general.changeCount }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        count += 1
        onNewString?(s)
    }
}

// MARK: - Overlays

/// Shown over the note while an image is dragged in: on the note's background, a 250 pt dashed orbit holding a
/// small framed dot and "Drop an image to capture text." in the editor font, both in `typeMain`.
final class DropOverlayView: NSView {
    var theme: Theme = .defaultLight { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(hex: theme.background).setFill()
        bounds.fill()
        let ink = NSColor(hex: theme.typeMain)
        // Drawn on a 700 × 479 design grid, scaled to fit 250 pt wide.
        let width = min(250, bounds.width - 40), k = width / 700, height = 479 * k
        let art = NSRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2 - 16, width: width, height: height)
        // A long dashed orbit rising to the right.
        let orbit = NSBezierPath(ovalIn: NSRect(x: -350 * k, y: -185 * k, width: 700 * k, height: 370 * k))
        var transform = AffineTransform(translationByX: art.minX + 381 * k, byY: art.minY + 228 * k)
        transform.rotate(byDegrees: -24.4)
        orbit.transform(using: transform)
        orbit.lineWidth = 6 * k
        orbit.setLineDash([18 * k, 12 * k], count: 2, phase: 0)
        ink.setStroke()
        orbit.stroke()
        // The "image": a square holding a large dot, sitting on the orbit's lower-left end.
        let frame = NSRect(x: art.minX + 3 * k, y: art.minY + 323 * k, width: 153 * k, height: 153 * k)
        NSColor(hex: theme.background).setFill()
        let square = NSBezierPath(roundedRect: frame, xRadius: 6 * k, yRadius: 6 * k)
        square.fill()
        square.lineWidth = 6 * k
        square.stroke()
        ink.setFill()
        let d = 63 * k
        NSBezierPath(ovalIn: NSRect(x: frame.midX - d / 2, y: frame.midY - d / 2, width: d, height: d)).fill()
        let text = "Drop an image to capture text." as NSString
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: Typography.font(), .foregroundColor: ink, .paragraphStyle: paragraph]
        text.draw(with: NSRect(x: 20, y: art.maxY + 16, width: bounds.width - 40, height: bounds.height - art.maxY - 16),
                  options: [.usesLineFragmentOrigin], attributes: attrs)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The link hover tip: the full address and the click hints in the editor font, `typeReverse` on an `accent1Main`
/// rounded rectangle padded 8 pt, with a soft shadow.
final class LinkTipView: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.33
        layer?.shadowRadius = 5
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Places the tip with its top-right corner at `point` (in the superview), kept inside `bounds`.
    func show(_ text: String, theme: Theme, endingAt point: NSPoint, in bounds: NSRect) {
        layer?.backgroundColor = NSColor(hex: theme.accent1Main).cgColor
        label.font = Typography.font()
        label.textColor = NSColor(hex: theme.typeReverse)
        label.stringValue = text
        label.preferredMaxLayoutWidth = max(120, bounds.width * 0.8 - 16)
        let size = label.fittingSize
        label.frame = NSRect(x: 8, y: 8, width: size.width, height: size.height)
        let tip = NSSize(width: size.width + 16, height: size.height + 16)
        let x = min(max(point.x - tip.width, bounds.minX + 8), bounds.maxX - tip.width - 8)
        let flipped = superview?.isFlipped ?? false
        let y = flipped ? point.y : point.y - tip.height
        frame = NSRect(x: x, y: max(bounds.minY + 4, min(y, bounds.maxY - tip.height - 4)), width: tip.width, height: tip.height)
        isHidden = false
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// One row of an inline command list: the `::` extension commands or the "/" palette commands.
struct CompletionRow: Equatable {
    var title: String
    /// Theme role of the title (the keyword's colour for keyword rows); `typeMain` otherwise.
    var titleRole: KeyPath<Theme, String> = \.typeMain
    /// "/" rows: 1…9, typed to pick the row.
    var number: Int?
    /// Small text after the title: the extension name (on a fill) or a keyword's summary (plain).
    var tag: String?
    var tagFilled = true
    /// Right-aligned: an extension action badge, or a palette shortcut in `typeLight`.
    var badge: String?
    var trailing: String?

    static func command(_ c: ExtensionCommandInfo) -> CompletionRow {
        CompletionRow(title: c.name, tag: c.extensionName, badge: c.action)
    }

    /// A palette command: keyword commands show the keyword in its colour plus what it does; others their title
    /// and shortcut.
    static func palette(_ c: PaletteCommand, number: Int?) -> CompletionRow {
        guard let keyword = c.keyword else {
            return CompletionRow(title: c.title, number: number, trailing: c.trailing)
        }
        let mode = NoteMode.keywordModes.first { $0.keywords.contains(keyword) } ?? .plain
        return CompletionRow(title: keyword, titleRole: keywordRole(mode), number: number, tag: c.detail, tagFilled: false)
    }

    /// The theme role of a keyword's colour (as `Theme.keyword(_:)` picks it).
    static func keywordRole(_ mode: NoteMode) -> KeyPath<Theme, String> {
        switch mode {
        case .plain: \.typeMain
        case .math: \.accent1Main
        case .list: \.accent2Main
        case .sum, .autopaste: \.accent3Main
        case .average, .code, .timer: \.accent4Main
        case .count: \.accent5Main
        }
    }
}

/// An inline command list under the caret (the `::` list and the "/" list). Keys stay with the text view; this
/// panel only displays and accepts clicks.
@MainActor
final class CompletionPanel {
    private let panel: NSPanel
    private let list = CompletionListView()
    let maxRows: Int
    var rows: [CompletionRow] { list.rows }
    var selectedIndex: Int { list.selected }
    var isVisible: Bool { panel.isVisible }
    /// Called with the clicked row's index.
    var onAccept: ((Int) -> Void)? {
        get { list.onAccept }
        set { list.onAccept = newValue }
    }

    init(footer: String, maxRows: Int) {
        self.maxRows = maxRows
        list.footer = footer
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.contentView = list
    }

    /// Shows `rows` (or the empty state) under the caret, about 60% as wide as the note window; above the caret
    /// when the caret is in the lower 40% of the window.
    func show(_ rows: [CompletionRow], theme: Theme, below screenRect: NSRect, parent: NSWindow?) {
        list.theme = theme
        list.rows = Array(rows.prefix(maxRows))
        list.selected = min(list.selected, max(0, list.rows.count - 1))
        let width = CompletionListView.width(forWindow: parent?.frame.width ?? 400)
        let height = CompletionListView.height(rows: list.rows.count)
        let frame = parent?.frame ?? .zero
        let above = parent != nil && screenRect.minY < frame.maxY - frame.height * 0.6
        let y = above ? screenRect.maxY + 6 : screenRect.minY - height - 6
        panel.setFrame(NSRect(x: screenRect.minX - 12, y: y, width: width, height: height), display: true)
        list.needsDisplay = true
        if !panel.isVisible {
            parent?.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        list.selected = 0
    }

    func move(_ delta: Int) {
        guard !list.rows.isEmpty else { return }
        list.selected = (list.selected + delta + list.rows.count) % list.rows.count
        list.needsDisplay = true
    }
}

/// Rows (12 × 8 pt padding): a bold chevron on the selected row (the row's number in the "/" list), the title, a
/// small tag and, right-aligned, an action badge (symbol + action on the action's colour) or a shortcut; a key-hint
/// footer below a divider.
final class CompletionListView: NSView {
    static let rowHeight: CGFloat = 34
    static let footerHeight: CGFloat = 30
    static func height(rows: Int) -> CGFloat { 6 + CGFloat(max(rows, 2)) * rowHeight + footerHeight }
    /// About 60% of the note window, never narrower than 280 pt.
    static func width(forWindow width: CGFloat) -> CGFloat { max(280, width * 0.6) }
    static let commandFooter = "↑↓ to navigate  •  ⇥ or ⏎ to select"
    static let paletteFooter = "1–9 or ⏎ to run  •  esc to close"

    var rows: [CompletionRow] = []
    var selected = 0
    var footer = CompletionListView.commandFooter
    /// `background` fill with a 1 px `typeSuperlight` border, 8 pt corners.
    var theme: Theme = .defaultLight {
        didSet {
            layer?.backgroundColor = NSColor(hex: theme.background).cgColor
            layer?.borderColor = NSColor(hex: theme.typeSuperlight).cgColor
            needsDisplay = true
        }
    }
    var onAccept: ((Int) -> Void)?
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let main = NSColor(hex: theme.typeMain), light = NSColor(hex: theme.typeLight)
        if rows.isEmpty {
            let title = NSAttributedString(string: "No commands found",
                                           attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: main])
            let detail = NSAttributedString(string: "Try a different search term",
                                            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: light])
            title.draw(at: NSPoint(x: (bounds.width - title.size().width) / 2, y: 14))
            detail.draw(at: NSPoint(x: (bounds.width - detail.size().width) / 2, y: 18 + title.size().height))
        }
        for (i, item) in rows.enumerated() {
            let row = NSRect(x: 0, y: 3 + CGFloat(i) * Self.rowHeight, width: bounds.width, height: Self.rowHeight)
            if i == selected {
                NSColor(hex: theme.typeHyperLight).setFill()
                row.fill()
            }
            if let number = item.number {
                let digit = NSAttributedString(string: "\(number)", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: light,
                ])
                digit.draw(at: NSPoint(x: 12 + 6 - digit.size().width / 2, y: row.midY - digit.size().height / 2))
            } else if i == selected {
                Self.symbol("chevron.right", size: 10, weight: .bold, color: main)
                    .map { draw($0, centeredAt: NSPoint(x: 12 + 6, y: row.midY)) }
            }
            // Right edge: the action badge (symbol and action name in `typeReverse` on the action's colour), or the
            // shortcut in `typeLight`.
            var right = row.maxX - 12
            if let action = item.badge {
                let (symbolName, fill) = Self.badge(action, theme: theme)
                let reverse = NSColor(hex: theme.typeReverse)
                let label = NSAttributedString(string: action,
                                               attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: reverse])
                let icon = Self.symbol(symbolName, size: 9, weight: .medium, color: reverse)
                let iconWidth = icon.map { $0.size.width + 4 } ?? 0
                let badgeRect = NSRect(x: right - (label.size().width + iconWidth + 16), y: row.midY - (label.size().height + 6) / 2,
                                       width: label.size().width + iconWidth + 16, height: label.size().height + 6)
                fill.setFill()
                NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4).fill()
                if let icon { draw(icon, centeredAt: NSPoint(x: badgeRect.minX + 8 + icon.size.width / 2, y: badgeRect.midY)) }
                label.draw(at: NSPoint(x: badgeRect.minX + 8 + iconWidth, y: badgeRect.minY + 3))
                right = badgeRect.minX
            } else if let trailing = item.trailing {
                let hint = NSAttributedString(string: trailing, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: light])
                hint.draw(at: NSPoint(x: right - hint.size().width, y: row.midY - hint.size().height / 2))
                right -= hint.size().width
            }

            let name = NSAttributedString(string: item.title, attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor(hex: theme[keyPath: item.titleRole]),
            ])
            let nameX: CGFloat = 12 + 12 + 8
            var nameEnd = right - 8
            if let tagText = item.tag {
                let tag = NSAttributedString(string: tagText, attributes: [
                    .font: NSFont.systemFont(ofSize: item.tagFilled ? 9 : 11), .foregroundColor: light,
                ])
                if item.tagFilled {
                    let tagRect = NSRect(x: right - 8 - (tag.size().width + 8), y: row.midY - (tag.size().height + 4) / 2,
                                         width: tag.size().width + 8, height: tag.size().height + 4)
                    if tagRect.minX > nameX + name.size().width + 8 {
                        NSColor(hex: theme.typeHyperLight).setFill()
                        NSBezierPath(roundedRect: tagRect, xRadius: 3, yRadius: 3).fill()
                        tag.draw(at: NSPoint(x: tagRect.minX + 4, y: tagRect.minY + 2))
                        nameEnd = tagRect.minX - 8
                    }
                } else {
                    // A plain description after the title, truncated to the space left.
                    let x = nameX + name.size().width + 10
                    if right - 8 - x > 40 {
                        tag.draw(with: NSRect(x: x, y: row.midY - tag.size().height / 2, width: right - 8 - x, height: tag.size().height),
                                 options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
                    }
                }
            }
            let nameRect = NSRect(x: nameX, y: row.midY - name.size().height / 2, width: nameEnd - nameX, height: name.size().height)
            name.draw(with: nameRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        let footerRect = NSRect(x: 0, y: bounds.height - Self.footerHeight, width: bounds.width, height: Self.footerHeight)
        NSColor(hex: theme.typeSuperlight).setFill()
        NSRect(x: 0, y: footerRect.minY, width: bounds.width, height: 1).fill()
        let hint = NSAttributedString(string: footer, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: light])
        hint.draw(at: NSPoint(x: 12, y: footerRect.midY - hint.size().height / 2))
    }

    private func draw(_ image: NSImage, centeredAt c: NSPoint) {
        let size = image.size
        image.draw(in: NSRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight).applying(.init(paletteColors: [color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    /// The badge symbol and fill for a command's action.
    static func badge(_ action: String, theme: Theme) -> (String, NSColor) {
        let badge = EditorLogic.actionBadge(action)
        return (badge.symbol, NSColor(hex: theme[keyPath: badge.role]))
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = Int((p.y - 3) / Self.rowHeight)
        guard rows.indices.contains(i), p.y < bounds.height - Self.footerHeight else { return }
        selected = i
        onAccept?(i)
    }
}

/// Offscreen views for rendering (JotterRender); nothing here is shown on screen.
public enum EditorPreview {
    /// The `::` command list as it appears under the caret in a note window `width` points wide.
    @MainActor public static func completionList(_ items: [ExtensionCommandInfo], selected: Int = 0, width: CGFloat) -> NSView {
        list(items.prefix(8).map(CompletionRow.command), footer: CompletionListView.commandFooter, selected: selected, width: width)
    }

    /// The "/" command list for `commands` as the palette returns them for `query`.
    @MainActor public static func slashList(_ commands: [PaletteCommand], query: String = "", selected: Int = 0,
                                            width: CGFloat) -> NSView {
        list(JotterEditor.slashRows(EditorLogic.Slash.ordered(commands, query: query)), footer: CompletionListView.paletteFooter, selected: selected,
             width: width)
    }

    @MainActor private static func list(_ rows: [CompletionRow], footer: String, selected: Int, width: CGFloat) -> NSView {
        let list = CompletionListView(frame: NSRect(x: 0, y: 0, width: CompletionListView.width(forWindow: width),
                                                    height: CompletionListView.height(rows: rows.count)))
        list.theme = Theme.current
        list.footer = footer
        list.rows = rows
        list.selected = selected
        return list
    }

    /// A note editor showing `text` with the find shelf open on the first `term` (and its Replace row when
    /// `replace`).
    @MainActor public static func findShelf(_ text: String, term: String, replace: Bool) -> NSView {
        let editor = JotterEditor()
        editor.load(Note(content: text))
        let r = (text as NSString).range(of: term)
        if r.location != NSNotFound { editor.textView.setSelectedRange(r) }
        editor.perform(replace ? .findAndReplace : .find)
        return editor.view
    }

    /// The image-drop overlay filling a note window of `size`.
    @MainActor public static func dropOverlay(size: NSSize) -> NSView {
        let overlay = DropOverlayView(frame: NSRect(origin: .zero, size: size))
        overlay.theme = Theme.current
        return overlay
    }

    /// The link hover tip, top-right corner at `point` inside `bounds`.
    @MainActor public static func linkTip(_ text: String, endingAt point: NSPoint, in bounds: NSRect) -> NSView {
        let tip = LinkTipView()
        tip.show(text, theme: Theme.current, endingAt: point, in: bounds)
        return tip
    }
}
