import AppKit
import JotterCore

// Views that make up the main note window: the hover-revealed top and bottom bars, the planets slot bar, the
// latest-note dot, note panes and the lock screen. The note fills the window; the bars float over it.

/// The main note window: titled (resizable, shadowed) with a transparent full-size title bar and no title text.
final class MainWindow: NSWindow {
    static let defaultSize = NSSize(width: 337, height: 386)

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.defaultSize),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        title = "Jotter"
        minSize = NSSize(width: 240, height: 180)
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenPrimary, .moveToActiveSpace]
        tabbingMode = .disallowed
    }

    var trafficLights: [NSButton] {
        [.closeButton, .miniaturizeButton, .zoomButton].compactMap { standardWindowButton($0) }
    }

    /// Centres the traffic lights on the top bar's icon row (17 pt down, 20 pt apart from x = 13).
    func alignTrafficLights() {
        for (i, button) in trafficLights.enumerated() {
            guard let container = button.superview else { continue }
            let size = button.frame.size
            button.setFrameOrigin(NSPoint(x: 13 + CGFloat(i) * 20 - size.width / 2,
                                          y: container.bounds.height - TitleBarView.iconRow - size.height / 2))
        }
    }
}

/// A chrome button: a line-art glyph tinted `typeMain` at 75%, a `typeHyperLight` rounded square on hover and
/// `typeLight` while pressed. The pin button turns `accent3Main` when pinned.
final class ChromeButton: NSView {
    static let side: CGFloat = 26
    private let icon: ChromeIcon
    private weak var target: AnyObject?
    private let action: Selector
    private var hovered = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }
    var isPinned = false { didSet { needsDisplay = true } }
    var theme: Theme = .defaultLight { didSet { needsDisplay = true } }

    init(_ icon: ChromeIcon, _ tooltip: String, target: AnyObject?, action: Selector) {
        self.icon = icon
        self.target = target
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        toolTip = tooltip
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tooltip)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: Self.side),
                                     heightAnchor.constraint(equalToConstant: Self.side)])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if pressed || hovered {
            NSColor(hex: pressed ? theme.typeLight : theme.typeHyperLight).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        let tint: NSColor = isPinned ? NSColor(hex: hovered ? theme.accent3Secondary : theme.accent3Main)
                                     : NSColor(hex: theme.typeMain).withAlphaComponent(0.75)
        let s = ChromeIcon.size
        let glyph = NSRect(x: (bounds.width - s) / 2, y: (bounds.height - s) / 2, width: s, height: s)
        let tinted = NSImage(size: glyph.size, flipped: false) { rect in
            self.icon.image.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: glyph)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseDragged(with event: NSEvent) { pressed = bounds.contains(convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        if inside { NSApp.sendAction(action, to: target, from: self) }
    }
    override func accessibilityPerformPress() -> Bool { NSApp.sendAction(action, to: target, from: self) }
}

/// A strip of chrome that fades in (200 ms) while the pointer is over it and passes clicks through while hidden.
class HoverBar: NSView {
    private(set) var isRevealed = false
    /// Keeps the bar visible regardless of hover (offscreen renders).
    var pinnedVisible = false { didSet { setRevealed(pinnedVisible, animated: false) } }
    var onHoverChange: ((Bool) -> Void)?
    let content = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        content.alphaValue = 0
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { setRevealed(true, animated: true) }
    override func mouseExited(with event: NSEvent) { setRevealed(pinnedVisible, animated: true) }

    func setRevealed(_ revealed: Bool, animated: Bool) {
        isRevealed = revealed
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? 0.2 : 0
            content.animator().alphaValue = revealed ? 1 : 0
        }
        onHoverChange?(revealed)
    }

    /// Hidden bars let clicks reach the note underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        isRevealed ? super.hitTest(point) : nil
    }
}

/// Top strip (34 pt): drags the window; on hover shows the traffic lights, Settings and Search on the left and
/// New Note and Pin on the right.
final class TitleBarView: HoverBar {
    static let height: CGFloat = 34
    /// Centre of the icon row, from the window top.
    static let iconRow: CGFloat = 17
    let pinButton: ChromeButton
    private let buttons: [ChromeButton]

    init(target: AnyObject) {
        let settings = ChromeButton(.settings, "Settings", target: target, action: #selector(Shell.openSettings(_:)))
        let search = ChromeButton(.search, "Search Notes", target: target, action: #selector(Shell.searchAllNotes(_:)))
        let new = ChromeButton(.new, "New Note", target: target, action: #selector(Shell.newNote(_:)))
        pinButton = ChromeButton(.pin, "Pin on Top", target: target, action: #selector(Shell.togglePin(_:)))
        buttons = [settings, search, new, pinButton]
        super.init(frame: .zero)
        buttons.forEach(content.addSubview)
        let side = ChromeButton.side
        NSLayoutConstraint.activate([
            settings.centerXAnchor.constraint(equalTo: content.leadingAnchor, constant: 81),
            search.centerXAnchor.constraint(equalTo: content.leadingAnchor, constant: 81 + side + 3),
            pinButton.centerXAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            new.centerXAnchor.constraint(equalTo: content.trailingAnchor, constant: -24 - side - 2),
        ] + buttons.map { $0.centerYAnchor.constraint(equalTo: content.topAnchor, constant: Self.iconRow) })
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Clicks on the strip itself (not a button) drag the window, double-click zooms — even while hidden.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let inside = super.hitTest(point)
        if inside != nil { return inside }
        return frame.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
    }

    func apply(theme: Theme) { buttons.forEach { $0.theme = theme } }

    func setPinned(_ pinned: Bool) {
        pinButton.isPinned = pinned
        pinButton.toolTip = pinned ? "Unpin from Top" : "Pin on Top"
    }
}

/// Bottom strip (30 pt), shown on hover: Move to The Void on the left, the note's date and position in the
/// middle, and Previous / Next / Latest / Export on the right.
final class BottomBarView: HoverBar {
    static let height: CGFloat = 30
    private let date = NSTextField(labelWithString: "")
    private let buttons: [ChromeButton]

    init(target: AnyObject) {
        let delete = ChromeButton(.delete, "Move to The Void", target: target, action: #selector(Shell.moveToVoid(_:)))
        let previous = ChromeButton(.previous, "Previous Note", target: target, action: #selector(Shell.previousNote(_:)))
        let next = ChromeButton(.next, "Next Note", target: target, action: #selector(Shell.nextNote(_:)))
        let front = ChromeButton(.front, "Go to Latest Note", target: target, action: #selector(Shell.goToFirstNote(_:)))
        let export = ChromeButton(.export, "Export", target: target, action: #selector(Shell.showExportMenu(_:)))
        buttons = [delete, previous, next, front, export]
        super.init(frame: .zero)
        date.font = .systemFont(ofSize: 12)
        date.alignment = .center
        date.lineBreakMode = .byTruncatingTail
        date.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        date.translatesAutoresizingMaskIntoConstraints = false
        (buttons + [date] as [NSView]).forEach(content.addSubview)
        let row = Self.height / 2
        var constraints = buttons.map { $0.centerYAnchor.constraint(equalTo: content.bottomAnchor, constant: -row) }
        constraints += [
            delete.centerXAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            export.centerXAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            front.centerXAnchor.constraint(equalTo: export.centerXAnchor, constant: -28),
            next.centerXAnchor.constraint(equalTo: front.centerXAnchor, constant: -28),
            previous.centerXAnchor.constraint(equalTo: next.centerXAnchor, constant: -28),
            date.centerYAnchor.constraint(equalTo: delete.centerYAnchor),
            date.leadingAnchor.constraint(greaterThanOrEqualTo: delete.trailingAnchor, constant: 4),
            date.trailingAnchor.constraint(lessThanOrEqualTo: previous.leadingAnchor, constant: -4),
        ]
        // The date sits centred in the free space between the left and right buttons.
        let gap = NSLayoutGuide()
        content.addLayoutGuide(gap)
        let centred = date.centerXAnchor.constraint(equalTo: gap.centerXAnchor)
        centred.priority = .defaultHigh
        constraints += [gap.leadingAnchor.constraint(equalTo: delete.trailingAnchor),
                        gap.trailingAnchor.constraint(equalTo: previous.leadingAnchor), centred]
        NSLayoutConstraint.activate(constraints)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// `text` is the note's date and/or position ("Jan 23, 2025  ·  14 of 18").
    func update(text: String, theme: Theme) {
        date.stringValue = text
        date.textColor = NSColor(hex: theme.typeLight)
        buttons.forEach { $0.theme = theme }
    }
}

/// The slot bar: a floating capsule of the nine planets (Mercury … Pluto) in `typeLight`, the open slot in
/// `accent1Main`. Hovering a planet names it and its note.
final class SlotsBarView: NSView, NSViewToolTipOwner {
    static let height: CGFloat = 24
    static let bottomInset: CGFloat = 16
    var onSelect: ((Int) -> Void)?
    /// Fades the bar in or out; a hidden bar lets clicks through to the note.
    var isShown = false {
        didSet {
            guard isShown != oldValue else { return }
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; animator().alphaValue = isShown ? 1 : 0 }
        }
    }
    private var titles: [Int: String] = [:]
    private var open: Int?
    private var theme: Theme = .defaultLight

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        alphaValue = 0
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.12).cgColor
        layer?.shadowRadius = 8
        layer?.shadowOffset = .zero
        layer?.shadowOpacity = 1
        layer?.cornerRadius = Self.height / 2
    }
    required init?(coder: NSCoder) { fatalError() }

    /// `titles[slot]` is the occupant's title; `open` is the slot shown (nil = the ephemeral deck).
    func update(titles: [Int: String], open: Int?, theme: Theme) {
        self.titles = titles
        self.open = open
        self.theme = theme
        layer?.backgroundColor = NSColor(hex: theme.background).withAlphaComponent(0.96).cgColor
        removeAllToolTips()
        for planet in Planet.allCases { addToolTip(hitRect(planet.rawValue), owner: self, userData: nil) }
        needsDisplay = true
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let slot = Planet.allCases.map(\.rawValue).first(where: { hitRect($0).contains(point) }),
              let planet = Planet(rawValue: slot) else { return "" }
        let what = titles[slot].map { $0.isEmpty ? "Empty note" : $0 } ?? "Empty slot — ⌃⌘\(slot + 1) puts this note here"
        return "\(planet.name) · \(what)"
    }

    private func center(_ slot: Int) -> NSPoint {
        let pad: CGFloat = 20
        let step = (bounds.width - pad * 2) / CGFloat(Planet.allCases.count - 1)
        return NSPoint(x: pad + CGFloat(slot) * step, y: bounds.midY)
    }

    private func hitRect(_ slot: Int) -> NSRect {
        let c = center(slot)
        return NSRect(x: c.x - 12, y: 0, width: 24, height: bounds.height)
    }

    override func layout() {
        super.layout()
        update(titles: titles, open: open, theme: theme)
    }

    override func draw(_ dirtyRect: NSRect) {
        let fill = NSColor(hex: theme.background)
        for planet in Planet.allCases {
            let slot = planet.rawValue
            let color = NSColor(hex: slot == open ? theme.accent1Main : theme.typeLight)
            planet.draw(at: center(slot), color: color, cutout: fill)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { isShown ? super.hitTest(point) : nil }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let slot = Planet.allCases.map(\.rawValue).first(where: { hitRect($0).contains(p) }) { onSelect?(slot) }
    }
}

/// One editor plus the lock screen that replaces it for locked notes.
final class NotePane: NSView {
    let editor: NoteEditing
    private(set) var noteID: UUID?
    private let lockView: LockScreenView

    init(editor: NoteEditing, onUnlock: @escaping () -> Void) {
        self.editor = editor
        lockView = LockScreenView(onUnlock: onUnlock)
        super.init(frame: .zero)
        for v in [editor.view, lockView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: leadingAnchor), v.trailingAnchor.constraint(equalTo: trailingAnchor),
                v.topAnchor.constraint(equalTo: topAnchor), v.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        lockView.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }

    var isShowingLock: Bool { !lockView.isHidden }

    func show(_ note: Note, locked: Bool) {
        if note.id != noteID || editor.note?.id != note.id { editor.load(note) }
        noteID = note.id
        editor.view.isHidden = locked
        lockView.isHidden = !locked
    }

    func clear() { noteID = nil }

    func apply(theme: Theme) { lockView.apply(theme: theme) }

    func contains(responder: NSResponder?) -> Bool {
        guard let view = responder as? NSView else { return false }
        return view.isDescendant(of: self)
    }
}

final class LockScreenView: NSView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "This note is locked")
    private let button: NSButton
    private let onUnlock: () -> Void

    init(onUnlock: @escaping () -> Void) {
        self.onUnlock = onUnlock
        button = NSButton(title: "Unlock", target: nil, action: nil)
        super.init(frame: .zero)
        button.target = self
        button.action = #selector(unlock)
        button.bezelStyle = .push
        button.keyEquivalent = "\r"
        icon.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked")
        icon.symbolConfiguration = .init(pointSize: 28, weight: .regular)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        let stack = NSStackView(views: [icon, label, button])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: centerXAnchor),
                                     stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func unlock() { onUnlock() }

    func apply(theme: Theme) {
        icon.contentTintColor = NSColor(hex: theme.typeLight)
        label.textColor = NSColor(hex: theme.typeMain)
    }
}
