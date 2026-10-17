import AppKit
import JotterCore

// Views that make up the main note window: the hover-revealed top and bottom bars, the planets slot bar, the
// latest-note dot, note panes and the lock screen. The note fills the window; the bars float over it.

/// The main note window: titled (resizable, shadowed) with a transparent full-size title bar and no title text.
final class MainWindow: NSWindow {
    /// Content size when no frame has been saved yet.
    static let defaultSize = NSSize(width: 350, height: 400)

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

    /// Centres the traffic lights on the top bar's button row (`TitleBarView.iconRow` down); x stays standard.
    func alignTrafficLights() {
        for button in trafficLights {
            guard let container = button.superview else { continue }
            let size = button.frame.size
            button.setFrameOrigin(NSPoint(x: button.frame.minX,
                                          y: container.bounds.height - TitleBarView.iconRow - size.height / 2))
        }
    }
}

/// Chrome tooltips: "Label - ⌘⇧F", the shortcut read from the main menu item that performs the same action.
enum ChromeTooltip {
    /// `label`, plus " - " and the shortcut of the main-menu item whose action is `action` (when there is one).
    @MainActor static func text(_ label: String, action: Selector) -> String {
        guard let item = NSApp?.mainMenu.flatMap({ find(action, in: $0) }), !item.keyEquivalent.isEmpty else { return label }
        let mods = item.keyEquivalentModifierMask
        return ChromeText.tooltip(label, shortcut: ChromeText.shortcut(key: item.keyEquivalent, command: mods.contains(.command),
                                                                       shift: mods.contains(.shift), option: mods.contains(.option),
                                                                       control: mods.contains(.control)))
    }

    private static func find(_ action: Selector, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.action == action { return item }
            if let sub = item.submenu, let found = find(action, in: sub) { return found }
        }
        return nil
    }
}

/// A chrome button (30 × 30): a line-art glyph drawn at 22 pt (4 pt inset) in `typeMain`, a `typeHyperLight`
/// rounded square (radius 5) on hover and `typeLight` while pressed; the pin turns `accent3Main` when pinned
/// (`accent3Secondary` on hover). On macOS 26 the background is a round Liquid Glass button instead, tinted for
/// the same states.
final class ChromeButton: NSView {
    static let side: CGFloat = 30
    static let cornerRadius: CGFloat = 5
    /// The glass flavour on macOS 26: regular for the top bar, clear for the bottom bar (whose hover tint is
    /// `typeHyperLight` at 20%).
    enum GlassStyle { case regular, clear }

    private let icon: ChromeIcon
    private weak var target: AnyObject?
    private let action: Selector
    private let label: String
    /// A fixed tooltip; otherwise the tooltip is `label` plus the main-menu shortcut of `action`.
    private let fixedTooltip: String?
    private let glassStyle: GlassStyle
    private var glass: NSView?
    private var glyphView: NSView?
    private var hovered = false { didSet { stateChanged() } }
    private var pressed = false { didSet { stateChanged() } }
    var isPinned = false { didSet { stateChanged() } }
    var theme: Theme = .defaultLight { didSet { stateChanged() } }

    init(_ icon: ChromeIcon, _ label: String, tooltip: String? = nil, glass: GlassStyle = .regular,
         target: AnyObject?, action: Selector) {
        self.icon = icon
        self.label = label
        fixedTooltip = tooltip
        glassStyle = glass
        self.target = target
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        toolTip = tooltip ?? label
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: Self.side),
                                     heightAnchor.constraint(equalToConstant: Self.side)])
        if #available(macOS 26, *) {
            let g = NSGlassEffectView()
            g.cornerRadius = Self.side / 2
            g.style = glass == .clear ? .clear : .regular
            g.frame = bounds
            g.autoresizingMask = [.width, .height]
            addSubview(g)
            self.glass = g
        }
        addGlyph()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Re-reads the tooltip's shortcut (it can change); the export button also changes its label.
    func refreshTooltip(label: String? = nil) {
        toolTip = fixedTooltip ?? ChromeTooltip.text(label ?? self.label, action: action)
    }

    private func stateChanged() {
        needsDisplay = true
        glyphView?.needsDisplay = true
        guard #available(macOS 26, *), let glass = glass as? NSGlassEffectView else { return }
        let hoverAlpha: CGFloat = glassStyle == .clear ? 0.2 : 1
        if pressed {
            glass.tintColor = NSColor(hex: theme.typeLight).withAlphaComponent(hoverAlpha)
        } else if isPinned {
            glass.tintColor = NSColor(hex: hovered ? theme.accent3Secondary : theme.accent3Main).withAlphaComponent(0.2)
        } else {
            glass.tintColor = hovered ? NSColor(hex: theme.typeHyperLight).withAlphaComponent(hoverAlpha) : nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if glass == nil, pressed || hovered {
            NSColor(hex: pressed ? theme.typeLight : theme.typeHyperLight).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()
        }
    }

    /// The glyph, in a child view so it sits above the glass.
    private func addGlyph() {
        let inset = (Self.side - ChromeIcon.size) / 2
        let view = GlyphView { [unowned self] rect in
            let tint = NSColor(hex: self.isPinned ? (self.hovered ? self.theme.accent3Secondary : self.theme.accent3Main)
                                                  : self.theme.typeMain)
            let tinted = NSImage(size: rect.size, flipped: false) { r in
                self.icon.image.draw(in: r)
                tint.set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: rect)
        }
        view.frame = bounds.insetBy(dx: inset, dy: inset)
        addSubview(view)
        glyphView = view
    }

    /// Clicks anywhere in the button (glass included) belong to the button.
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

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

/// A view that draws with a closure and ignores the mouse.
private final class GlyphView: NSView {
    private let drawing: (NSRect) -> Void
    init(_ drawing: @escaping (NSRect) -> Void) {
        self.drawing = drawing
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) { drawing(bounds) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A strip of chrome that fades in (300 ms) while the pointer is over it and passes clicks through while hidden.
class HoverBar: NSView {
    static let fadeDuration: TimeInterval = 0.3
    private(set) var isRevealed = false
    /// Keeps the bar visible regardless of hover (offscreen renders).
    var pinnedVisible = false { didSet { setRevealed(pinnedVisible, animated: false) } }
    var onHoverChange: ((Bool) -> Void)?
    let content = NSView()
    /// Behind the buttons, fading with them: nothing in an opaque window; in a translucent one a `hudWindow`
    /// material blended within the window, or the theme background with "Use solid colors for top and bottom bars
    /// when translucent".
    enum Backdrop: Equatable { case none, material, solid(NSColor) }
    private let material = NSVisualEffectView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        content.alphaValue = 0
        content.wantsLayer = true
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        material.material = .hudWindow
        material.blendingMode = .withinWindow
        material.state = .active
        material.isHidden = true
        material.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(material)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor),
            material.leadingAnchor.constraint(equalTo: content.leadingAnchor), material.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            material.topAnchor.constraint(equalTo: content.topAnchor), material.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setBackdrop(_ backdrop: Backdrop) {
        material.isHidden = backdrop != .material
        if case .solid(let color) = backdrop { content.layer?.backgroundColor = color.cgColor } else { content.layer?.backgroundColor = nil }
    }

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
            ctx.duration = animated ? Self.fadeDuration : 0
            content.animator().alphaValue = revealed ? 1 : 0
        }
        onHoverChange?(revealed)
    }

    /// Hidden bars let clicks reach the note underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        isRevealed ? super.hitTest(point) : nil
    }
}

/// Top strip: drags the window; on hover shows the traffic lights, Settings and Search on the left and New Note
/// and Pin on the right. The bar is 30 pt tall and its buttons (and the traffic lights) sit 5 pt below its middle,
/// so they reach 5 pt past it; the strip covers them.
final class TitleBarView: HoverBar {
    static let height: CGFloat = 35
    /// Centre of the button row, from the window top: the 30 pt bar's middle plus 5.
    static let iconRow: CGFloat = 20
    /// Left buttons start after the traffic lights; the right ones end 10 pt from the edge.
    static let leadingInset: CGFloat = 80
    static let trailingInset: CGFloat = 10
    /// Gap between neighbouring buttons: none, or 5 pt between the round glass buttons of macOS 26.
    static var spacing: CGFloat { if #available(macOS 26, *) { 5 } else { 0 } }

    let pinButton: ChromeButton
    private let buttons: [ChromeButton]

    init(target: AnyObject) {
        let settings = ChromeButton(.settings, "Settings", tooltip: "Settings - ⌘+,", target: target,
                                    action: #selector(Shell.openSettings(_:)))
        let search = ChromeButton(.search, "Search Notes", target: target, action: #selector(Shell.searchAllNotes(_:)))
        let new = ChromeButton(.new, "New Note", target: target, action: #selector(Shell.newNote(_:)))
        pinButton = ChromeButton(.pin, "Pin Jotter to Top", target: target, action: #selector(Shell.togglePin(_:)))
        buttons = [settings, search, new, pinButton]
        super.init(frame: .zero)
        buttons.forEach(content.addSubview)
        let side = ChromeButton.side, gap = Self.spacing
        NSLayoutConstraint.activate([
            settings.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.leadingInset),
            search.leadingAnchor.constraint(equalTo: settings.leadingAnchor, constant: side + gap),
            pinButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.trailingInset),
            new.trailingAnchor.constraint(equalTo: pinButton.trailingAnchor, constant: -(side + gap)),
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

    override func setRevealed(_ revealed: Bool, animated: Bool) {
        if revealed { buttons.forEach { $0.refreshTooltip() } }
        super.setRevealed(revealed, animated: animated)
    }

    func apply(theme: Theme) { buttons.forEach { $0.theme = theme } }

    func setPinned(_ pinned: Bool) { pinButton.isPinned = pinned }
}

/// Bottom strip (40 pt), shown on hover: Delete on the left; the note's date and position ("Oct 17, 2026 | 3 of
/// 12") in the middle, in the system's grey 11 pt subheadline; Previous / Next / First and Export on the right.
/// Buttons are 30 pt, centred 20 pt above the bottom, 10 pt in from the sides and 8 pt apart.
final class BottomBarView: HoverBar {
    static let height: CGFloat = 40
    static let sideInset: CGFloat = 10
    static let spacing: CGFloat = 8
    static let textFont = NSFont.preferredFont(forTextStyle: .subheadline)
    private let info = NSStackView()
    private let buttons: [ChromeButton]
    let exportButton: ChromeButton

    init(target: AnyObject) {
        let delete = ChromeButton(.delete, "Delete Note", glass: .clear, target: target, action: #selector(Shell.moveToVoid(_:)))
        let previous = ChromeButton(.previous, "Previous Note", glass: .clear, target: target, action: #selector(Shell.previousNote(_:)))
        let next = ChromeButton(.next, "Next Note", glass: .clear, target: target, action: #selector(Shell.nextNote(_:)))
        let front = ChromeButton(.front, "Go to First Note", glass: .clear, target: target, action: #selector(Shell.goToFirstNote(_:)))
        exportButton = ChromeButton(.export, "Export", glass: .clear, target: target, action: #selector(Shell.exportFromBar(_:)))
        buttons = [delete, previous, next, front, exportButton]
        super.init(frame: .zero)
        info.orientation = .horizontal
        info.spacing = Self.spacing
        info.setHuggingPriority(.defaultHigh, for: .horizontal)
        info.setClippingResistancePriority(.defaultLow, for: .horizontal)
        info.translatesAutoresizingMaskIntoConstraints = false
        (buttons + [info] as [NSView]).forEach(content.addSubview)
        let row = Self.height / 2, step = ChromeButton.side + Self.spacing
        var constraints = buttons.map { $0.centerYAnchor.constraint(equalTo: content.bottomAnchor, constant: -row) }
        constraints += [
            delete.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.sideInset),
            exportButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.sideInset),
            front.trailingAnchor.constraint(equalTo: exportButton.trailingAnchor, constant: -step),
            next.trailingAnchor.constraint(equalTo: front.trailingAnchor, constant: -step),
            previous.trailingAnchor.constraint(equalTo: next.trailingAnchor, constant: -step),
            info.centerYAnchor.constraint(equalTo: delete.centerYAnchor),
            info.leadingAnchor.constraint(greaterThanOrEqualTo: delete.trailingAnchor, constant: Self.spacing),
            info.trailingAnchor.constraint(lessThanOrEqualTo: previous.leadingAnchor, constant: -Self.spacing),
        ]
        // The text sits centred in the free space between the left and right buttons.
        let gap = NSLayoutGuide()
        content.addLayoutGuide(gap)
        let centred = info.centerXAnchor.constraint(equalTo: gap.centerXAnchor)
        centred.priority = .defaultHigh
        constraints += [gap.leadingAnchor.constraint(equalTo: delete.trailingAnchor),
                        gap.trailingAnchor.constraint(equalTo: previous.leadingAnchor), centred]
        NSLayoutConstraint.activate(constraints)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func setRevealed(_ revealed: Bool, animated: Bool) {
        if revealed { buttons.filter { $0 !== exportButton }.forEach { $0.refreshTooltip() } }
        super.setRevealed(revealed, animated: animated)
    }

    /// `parts` are the note's date and position ("Oct 17, 2026", "3 of 12", …), shown with "|" between them.
    func update(parts: [String], theme: Theme) {
        let texts = Array(parts.map { [$0] }.joined(separator: ["|"]))
        while info.arrangedSubviews.count > texts.count { info.arrangedSubviews.last?.removeFromSuperview() }
        while info.arrangedSubviews.count < texts.count {
            let label = NSTextField(labelWithString: "")
            label.font = Self.textFont
            label.textColor = .systemGray
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            info.addArrangedSubview(label)
        }
        for (view, text) in zip(info.arrangedSubviews, texts) { (view as? NSTextField)?.stringValue = text }
        buttons.forEach { $0.theme = theme }
    }
}

/// The slot bar: a floating capsule of the nine planets (Mercury … Pluto). Planets sit in 22 pt frames 3 pt apart,
/// in `typeLight` at 65%; the open slot gets a 28 pt frame, scaled 1.18, in `accent1Main`. The capsule is 32 pt
/// tall with 16 pt side padding, filled with the theme background, a hairline grey border and a faint accent glow
/// (Liquid Glass tinted with the background on macOS 26). Hovering a planet names its slot.
final class SlotsBarView: NSView, NSViewToolTipOwner {
    static let height: CGFloat = 32
    static let bottomInset: CGFloat = 10
    static let openPlanetScale: CGFloat = 1.18
    static let fadeDuration: TimeInterval = 0.6
    var onSelect: ((Int) -> Void)?
    /// Fades the bar in or out; a hidden bar lets clicks through to the note.
    var isShown = false {
        didSet {
            guard isShown != oldValue else { return }
            NSAnimationContext.runAnimationGroup { $0.duration = Self.fadeDuration; animator().alphaValue = isShown ? 1 : 0 }
        }
    }
    private var titles: [Int: String] = [:]
    private var open: Int?
    private var theme: Theme = .defaultLight
    private var glass: NSView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        alphaValue = 0
        layer?.masksToBounds = false
        layer?.cornerRadius = Self.height / 2
        if #available(macOS 26, *) {
            let g = NSGlassEffectView()
            g.cornerRadius = Self.height / 2
            g.frame = bounds
            g.autoresizingMask = [.width, .height]
            addSubview(g)
            glass = g
        } else {
            layer?.borderWidth = 1
            layer?.shadowRadius = 7
            layer?.shadowOffset = .zero
            layer?.shadowOpacity = 0.2
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize { NSSize(width: SlotBarLayout.width(open: open), height: Self.height) }

    /// `titles[slot]` is the occupant's title; `open` is the slot shown (nil = the ephemeral deck).
    func update(titles: [Int: String], open: Int?, theme: Theme) {
        self.titles = titles
        if open != self.open { invalidateIntrinsicContentSize() }
        self.open = open
        self.theme = theme
        let background = NSColor(hex: theme.background)
        if #available(macOS 26, *), let glass = glass as? NSGlassEffectView {
            glass.tintColor = background.withAlphaComponent(0.3)
        } else {
            layer?.backgroundColor = background.cgColor
            layer?.borderColor = NSColor.systemGray.withAlphaComponent(0.15).cgColor
            layer?.shadowColor = NSColor(hex: theme.accent1Main).withAlphaComponent(0.45).cgColor
        }
        removeAllToolTips()
        for planet in Planet.allCases { addToolTip(slotRect(planet.rawValue), owner: self, userData: nil) }
        needsDisplay = true
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let slot = Planet.allCases.map(\.rawValue).first(where: { slotRect($0).contains(point) }) else { return "" }
        return "Slot \(slot + 1)"
    }

    /// The frame a planet is laid out in (its column, full height for hit testing).
    private func slotRect(_ slot: Int) -> NSRect {
        NSRect(x: SlotBarLayout.x(of: slot, open: open), y: 0, width: SlotBarLayout.frames(open: open)[slot], height: bounds.height)
    }

    override func layout() {
        super.layout()
        update(titles: titles, open: open, theme: theme)
    }

    override func draw(_ dirtyRect: NSRect) {
        for planet in Planet.allCases {
            let slot = planet.rawValue
            let column = slotRect(slot)
            let isOpen = slot == open
            let side = column.width * (isOpen ? Self.openPlanetScale : 1)
            let rect = NSRect(x: column.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
            let color = isOpen ? NSColor(hex: theme.accent1Main) : NSColor(hex: theme.typeLight).withAlphaComponent(0.65)
            planet.draw(in: rect, color: color)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { isShown && frame.contains(point) ? self : nil }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let slot = Planet.allCases.map(\.rawValue).first(where: { slotRect($0).contains(p) }) { onSelect?(slot) }
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


/// Shown instead of a locked note: a 32 pt medium lock at 60%, "This note is locked" in Menlo 14 and an Unlock
/// button (Touch ID glyph, Menlo 12, Return), 14 pt apart, in the theme's `typeSubtle`.
final class LockScreenView: NSView {
    static let spacing: CGFloat = 14
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
        button.font = NSFont(name: "Menlo", size: 12)
        button.image = NSImage(systemSymbolName: "touchid", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        icon.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked")
        icon.symbolConfiguration = .init(pointSize: 32, weight: .medium)
        label.font = NSFont(name: "Menlo", size: 14)
        let stack = NSStackView(views: [icon, label, button])
        stack.orientation = .vertical
        stack.spacing = Self.spacing
        stack.setCustomSpacing(Self.spacing + 2, after: icon)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: centerXAnchor),
                                     stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func unlock() { onUnlock() }

    func apply(theme: Theme) {
        let color = NSColor(hex: theme.typeSubtle)
        icon.contentTintColor = color.withAlphaComponent(0.6)
        label.textColor = color
    }
}
