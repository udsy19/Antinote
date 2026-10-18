import AppKit
import UniformTypeIdentifiers
import Vision
import SuperNotesCore

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
    /// Keyword rows show the title as a chip tinted with its colour.
    var isKeyword = false
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
        return CompletionRow(title: keyword, titleRole: keywordRole(mode), isKeyword: true, number: number, tag: c.detail,
                             tagFilled: false)
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

/// The inline command list under the caret: the one popover behind both the `::` list and the "/" list. Keys stay
/// with the text view; the list takes the mouse without ever becoming key: the row under the pointer is selected,
/// a click runs it, the wheel scrolls, and a click anywhere else (or leaving the app) closes it.
@MainActor
final class CompletionPanel {
    /// Rows kept for scrolling; `visibleRows` of them show at once.
    static let maxItems = 60
    private let panel = CompletionWindow()
    private let list: CompletionListView
    private var clickMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    var rows: [CompletionRow] { list.rows }
    var selectedIndex: Int { list.model.selected }
    var isVisible: Bool { panel.isVisible }
    /// Called with the clicked row's index.
    var onAccept: ((Int) -> Void)? {
        get { list.onAccept }
        set { list.onAccept = newValue }
    }
    /// Called after a click outside the list, or the app or note window losing focus, closed it.
    var onDismiss: (() -> Void)?

    init(footer: String, visibleRows: Int) {
        list = CompletionListView(footer: footer, visibleRows: visibleRows)
        panel.contentView = list
    }

    /// Shows `rows` (or the empty state) under the caret line `caret` (screen coordinates), about 60% as wide as
    /// the note window; above it when the caret is low in the window or near the bottom of the screen.
    func show(_ rows: [CompletionRow], theme: Theme, below caret: NSRect, parent: NSWindow?) {
        list.theme = theme
        list.rows = Array(rows.prefix(Self.maxItems))
        let size = CGSize(width: CompletionListView.width(forWindow: parent?.frame.width ?? 400), height: list.model.height)
        let screen = (parent?.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: -1e5, y: -1e5, width: 2e5, height: 2e5)
        let frame = EditorLogic.CommandList.frame(size: size, anchor: caret, window: parent?.frame ?? .zero, screen: screen)
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
        list.needsDisplay = true
        guard !panel.isVisible else { return }
        parent?.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        watchForDismissal(parent: parent)
    }

    func hide() {
        stopWatching()
        guard panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        list.model.rewind()
    }

    func move(_ delta: Int) {
        list.model.move(delta)
        list.needsDisplay = true
    }

    /// Clicks outside the list close it (and still reach what was clicked); so does the app or the note window
    /// losing focus.
    private func watchForDismissal(parent: NSWindow?) {
        stopWatching()
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window !== self.panel else { return }
                self.dismiss()
            }
            return event
        }
        let center = NotificationCenter.default
        let dismiss: @Sendable (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.dismiss() } }
        observers = [center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main, using: dismiss)]
        if let parent {
            observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: parent, queue: .main, using: dismiss))
        }
    }

    private func stopWatching() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func dismiss() {
        guard panel.isVisible else { return }
        hide()
        onDismiss?()
    }
}

/// A borderless panel that never becomes key or main, so the note's text view keeps the keyboard and the caret
/// while the list under it is clicked, hovered and scrolled.
private final class CompletionWindow: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 100), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The list: `background` with a 1 px `typeSuperlight` border and 8 pt corners, rows 28 pt tall. The selected row
/// (the one under the pointer, or picked with ↑↓) gets a rounded `typeHyperLight` fill and a bold chevron. A row
/// shows its title (a keyword as a chip tinted with its colour, descriptions lined up after the widest chip and
/// cut short with "…"), then, right-aligned, an action badge or shortcut and the "/" list's 1–9 in a muted mono.
/// A key-hint footer sits under a divider; a thin bar on the right shows the scroll position when rows overflow.
final class CompletionListView: NSView {
    static let commandFooter = "↑↓ to navigate  •  ⇥ or ⏎ to select"
    static let paletteFooter = "1–9 or ⏎ to run  •  esc to close"
    /// Rows shown at once in the `::` list and the "/" list.
    static let commandRows = 8
    static let paletteRows = 9
    /// About 60% of the note window, never narrower than 280 pt.
    static func width(forWindow width: CGFloat) -> CGFloat { max(280, width * 0.6) }
    private static let rowHeight = CGFloat(EditorLogic.CommandList.rowHeight)
    private static let footerHeight = CGFloat(EditorLogic.CommandList.footerHeight)
    /// Left edge of the titles (after the chevron slot) and the side padding.
    private static let titleX: CGFloat = 30
    private static let sidePadding: CGFloat = 12
    private static let numberColumn: CGFloat = 18

    var rows: [CompletionRow] = [] {
        didSet { model.reset(count: rows.count); needsDisplay = true }
    }
    var model: EditorLogic.CommandList
    var footer: String
    var theme: Theme = .defaultLight {
        didSet {
            layer?.backgroundColor = NSColor(hex: theme.background).cgColor
            layer?.borderColor = NSColor(hex: theme.typeSuperlight).cgColor
            needsDisplay = true
        }
    }
    var onAccept: ((Int) -> Void)?
    /// The row the mouse went down on: releasing over the same row runs it.
    private var pressedRow: Int?
    private var scrollRemainder: CGFloat = 0
    /// Hover only follows real pointer movement, not rows changing under a still pointer.
    private var lastPointer: NSPoint?
    override var isFlipped: Bool { true }

    init(footer: String, visibleRows: Int) {
        self.footer = footer
        model = EditorLogic.CommandList(visible: visibleRows)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let light = NSColor(hex: theme.typeLight)
        if rows.isEmpty { drawEmptyState() }
        let listArea = NSRect(x: 0, y: EditorLogic.CommandList.topPadding, width: bounds.width,
                              height: CGFloat(model.shownRows) * Self.rowHeight)
        let chipColumn = rows.filter(\.isKeyword).map { chip($0).size().width + 12 }.max() ?? 0
        NSGraphicsContext.saveGraphicsState()
        listArea.clip()
        for i in model.top..<min(model.count, model.top + model.visible) {
            let row = NSRect(x: 0, y: CGFloat(model.y(of: i)), width: bounds.width, height: Self.rowHeight)
            drawRow(rows[i], in: row, selected: i == model.selected, chipColumn: chipColumn)
        }
        NSGraphicsContext.restoreGraphicsState()
        if model.canScroll {
            let track = listArea.insetBy(dx: 0, dy: 4)
            let thumbHeight = max(16, track.height * CGFloat(model.visible) / CGFloat(model.count))
            let travel = track.height - thumbHeight
            let maxTop = CGFloat(model.count - model.visible)
            let thumb = NSRect(x: bounds.maxX - 5, y: track.minY + travel * CGFloat(model.top) / maxTop, width: 3, height: thumbHeight)
            light.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: thumb, xRadius: 1.5, yRadius: 1.5).fill()
        }
        let footerRect = NSRect(x: 0, y: bounds.height - Self.footerHeight, width: bounds.width, height: Self.footerHeight)
        NSColor(hex: theme.typeSuperlight).setFill()
        NSRect(x: 0, y: footerRect.minY, width: bounds.width, height: 1).fill()
        let hint = NSAttributedString(string: footer, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: light])
        hint.draw(at: NSPoint(x: Self.sidePadding, y: footerRect.midY - hint.size().height / 2 + 0.5))
    }

    private func drawEmptyState() {
        let title = NSAttributedString(string: "No commands found", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor(hex: theme.typeMain),
        ])
        let detail = NSAttributedString(string: "Try a different search term", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(hex: theme.typeLight),
        ])
        title.draw(at: NSPoint(x: (bounds.width - title.size().width) / 2, y: 12))
        detail.draw(at: NSPoint(x: (bounds.width - detail.size().width) / 2, y: 16 + title.size().height))
    }

    /// A keyword's chip text: system 12 medium in the keyword's colour.
    private func chip(_ item: CompletionRow) -> NSAttributedString {
        NSAttributedString(string: item.title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor(hex: theme[keyPath: item.titleRole]),
        ])
    }

    private func drawRow(_ item: CompletionRow, in row: NSRect, selected: Bool, chipColumn: CGFloat) {
        let main = NSColor(hex: theme.typeMain), light = NSColor(hex: theme.typeLight)
        if selected {
            NSColor(hex: theme.typeHyperLight).setFill()
            NSBezierPath(roundedRect: row.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5).fill()
            Self.symbol("chevron.right", size: 9, weight: .bold, color: main)
                .map { draw($0, centeredAt: NSPoint(x: 18, y: row.midY)) }
        }
        // Right edge: the "/" list's number, then an action badge (symbol and action in `typeReverse` on the
        // action's colour) or a shortcut in `typeLight`.
        var right = row.maxX - Self.sidePadding
        if let number = item.number {
            let digit = NSAttributedString(string: "\(number)", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: light.withAlphaComponent(0.85),
            ])
            digit.draw(at: NSPoint(x: right - digit.size().width, y: row.midY - digit.size().height / 2))
            right -= Self.numberColumn
        }
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
        right -= 8

        if item.isKeyword {
            let text = chip(item)
            let size = text.size()
            let chipRect = NSRect(x: Self.titleX, y: row.midY - (size.height + 4) / 2, width: size.width + 12, height: size.height + 4)
            NSColor(hex: theme[keyPath: item.titleRole]).withAlphaComponent(theme.isDark ? 0.2 : 0.12).setFill()
            NSBezierPath(roundedRect: chipRect, xRadius: 4, yRadius: 4).fill()
            text.draw(at: NSPoint(x: chipRect.minX + 6, y: chipRect.minY + 2))
            if let summary = item.tag {
                let x = Self.titleX + chipColumn + 10
                Self.truncated(summary, font: .systemFont(ofSize: 11), color: light, in: NSRect(x: x, y: row.minY, width: right - x, height: row.height))
            }
            return
        }
        let titleFont = NSFont.systemFont(ofSize: 12)
        var titleEnd = right
        if let tagText = item.tag {
            let tagFont = NSFont.systemFont(ofSize: item.tagFilled ? 9 : 11)
            let titleWidth = NSAttributedString(string: item.title, attributes: [.font: titleFont]).size().width
            if item.tagFilled {
                // The extension's name on a small fill, right-aligned, when there's room after the title.
                let tag = NSAttributedString(string: tagText, attributes: [.font: tagFont, .foregroundColor: light])
                let tagRect = NSRect(x: right - (tag.size().width + 8), y: row.midY - (tag.size().height + 4) / 2,
                                     width: tag.size().width + 8, height: tag.size().height + 4)
                if tagRect.minX > Self.titleX + titleWidth + 8 {
                    NSColor(hex: theme.typeHyperLight).blended(withFraction: selected ? 0.25 : 0, of: NSColor(hex: theme.typeSuperlight))?.setFill()
                    NSBezierPath(roundedRect: tagRect, xRadius: 3, yRadius: 3).fill()
                    tag.draw(at: NSPoint(x: tagRect.minX + 4, y: tagRect.minY + 2))
                    titleEnd = tagRect.minX - 8
                }
            } else {
                let x = Self.titleX + titleWidth + 10
                if right - x > 40 {
                    Self.truncated(tagText, font: tagFont, color: light, in: NSRect(x: x, y: row.minY, width: right - x, height: row.height))
                }
            }
        }
        Self.truncated(item.title, font: titleFont, color: NSColor(hex: theme[keyPath: item.titleRole]),
                       in: NSRect(x: Self.titleX, y: row.minY, width: titleEnd - Self.titleX, height: row.height))
    }

    /// One line of `text`, vertically centred in `rect` and cut short with "…".
    private static func truncated(_ text: String, font: NSFont, color: NSColor, in rect: NSRect) {
        guard rect.width > 4 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let s = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
        let height = s.size().height
        s.draw(with: NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height),
               options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
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

    // MARK: Mouse

    /// The first click on the (never key) list counts: it picks a row.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let pointer = NSEvent.mouseLocation
        guard pointer != lastPointer else { return }
        lastPointer = pointer
        hover(convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        pressedRow = model.row(atY: Double(p.y))
        hover(p)
    }

    override func mouseDragged(with event: NSEvent) { hover(convert(event.locationInWindow, from: nil)) }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        defer { pressedRow = nil }
        guard let row = model.row(atY: Double(p.y)), row == pressedRow else { return }
        onAccept?(row)
    }

    override func scrollWheel(with event: NSEvent) {
        guard model.canScroll else { return }
        scrollRemainder += event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * Self.rowHeight
        let steps = Int((scrollRemainder / Self.rowHeight).rounded(.towardZero))
        guard steps != 0 else { return }
        scrollRemainder -= CGFloat(steps) * Self.rowHeight
        model.scroll(by: -steps)
        if let window { hover(convert(window.mouseLocationOutsideOfEventStream, from: nil)) }
        needsDisplay = true
    }

    /// The row under the pointer becomes the selection (↑↓ carry on from it).
    private func hover(_ p: NSPoint) {
        guard let row = model.row(atY: Double(p.y)), row != model.selected else { return }
        model.select(row)
        needsDisplay = true
    }
}

/// Offscreen views for rendering (SuperNotesRender); nothing here is shown on screen.
public enum EditorPreview {
    /// The `::` command list as it appears under the caret in a note window `width` points wide.
    @MainActor public static func completionList(_ items: [ExtensionCommandInfo], selected: Int = 0, width: CGFloat) -> NSView {
        list(items.map(CompletionRow.command), footer: CompletionListView.commandFooter, visibleRows: CompletionListView.commandRows,
             selected: selected, width: width)
    }

    /// The "/" command list for `commands` as the palette returns them for `query`, with row `selected` picked
    /// (the row under the pointer, when hovering) and scrolled into view.
    @MainActor public static func slashList(_ commands: [PaletteCommand], query: String = "", selected: Int = 0,
                                            width: CGFloat) -> NSView {
        list(SuperNotesEditor.slashRows(EditorLogic.Slash.ordered(commands, query: query)), footer: CompletionListView.paletteFooter,
             visibleRows: CompletionListView.paletteRows, selected: selected, width: width)
    }

    /// A note editor of `size` showing `text` (caret at the end) with `list` (from `completionList` or
    /// `slashList`) placed against the character at `anchor` (the end when nil) as the app places it, the canvas
    /// standing in for the screen. With `pointerOn`, an arrow pointer rests on that row (the hover state).
    @MainActor public static func note(_ text: String, size: NSSize, showing list: NSView, anchor: Int? = nil,
                                       pointerOn row: Int? = nil) -> NSView {
        let editor = SuperNotesEditor()
        editor.load(Note(content: text))
        let view = editor.view
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        let tv = editor.textView
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return view }
        lm.ensureLayout(for: tc)
        let length = (tv.string as NSString).length, index = min(anchor ?? length, length)
        let glyph = lm.glyphIndexForCharacter(at: max(0, min(index, length - 1)))
        let box = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc)
        var line = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        line.origin.x = index < length ? box.minX : box.maxX
        line.size.width = 1
        line = line.offsetBy(dx: tv.textContainerOrigin.x, dy: tv.textContainerOrigin.y)
        let anchor = view.convert(tv.convert(line, to: nil), from: nil)
        list.frame = EditorLogic.CommandList.frame(size: list.frame.size, anchor: anchor, window: view.bounds, screen: view.bounds)
        view.addSubview(list)
        if let row, let list = list as? CompletionListView, let arrow = NSCursor.arrow.image.copy() as? NSImage {
            let y = list.model.y(of: row) + EditorLogic.CommandList.rowHeight / 2
            let tip = view.convert(NSPoint(x: list.bounds.width * 0.55, y: y), from: list)
            let pointer = NSImageView(image: arrow)
            pointer.frame = NSRect(x: tip.x - NSCursor.arrow.hotSpot.x, y: tip.y - arrow.size.height + NSCursor.arrow.hotSpot.y,
                                   width: arrow.size.width, height: arrow.size.height)
            view.addSubview(pointer)
        }
        return view
    }

    @MainActor private static func list(_ rows: [CompletionRow], footer: String, visibleRows: Int, selected: Int,
                                        width: CGFloat) -> NSView {
        let list = CompletionListView(footer: footer, visibleRows: visibleRows)
        list.theme = Theme.current
        list.rows = rows
        list.model.select(selected)
        list.frame = NSRect(x: 0, y: 0, width: CompletionListView.width(forWindow: width), height: list.model.height)
        return list
    }

    /// A note editor showing `text` with the find shelf open on the first `term` (and its Replace row when
    /// `replace`).
    @MainActor public static func findShelf(_ text: String, term: String, replace: Bool) -> NSView {
        let editor = SuperNotesEditor()
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
