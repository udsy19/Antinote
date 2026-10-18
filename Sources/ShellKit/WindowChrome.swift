import AppKit
import SuperNotesCore

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
        title = "Super Notes"
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
        ChromeText.tooltip(label, shortcut: shortcut(action: action))
    }

    /// The shortcut ("⌃⌘3") of the main-menu item whose action is `action` (and tag `tag`, when given), if it has one.
    @MainActor static func shortcut(action: Selector, tag: Int? = nil) -> String? {
        guard let menu = NSApp?.mainMenu ?? MainMenu.built, let item = find(action, tag: tag, in: menu), !item.keyEquivalent.isEmpty
        else { return nil }
        let mods = item.keyEquivalentModifierMask
        return ChromeText.shortcut(key: item.keyEquivalent, command: mods.contains(.command), shift: mods.contains(.shift),
                                   option: mods.contains(.option), control: mods.contains(.control))
    }

    private static func find(_ action: Selector, tag: Int?, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.action == action, tag == nil || item.tag == tag { return item }
            if let sub = item.submenu, let found = find(action, tag: tag, in: sub) { return found }
        }
        return nil
    }
}

/// A chrome button on `ChromeMetrics` (30 × 30): a line-art glyph drawn at 22 pt (4 pt inset) in `typeMain`, a
/// `typeHyperLight` rounded square (radius 5) on hover and `typeLight` while pressed; the pin turns `accent3Main`
/// when pinned (`accent3Secondary` on hover). Disabled, the glyph fades to 35 % and the mouse does nothing. With
/// Full Keyboard Access the button takes the focus (a rounded focus ring) and Space or Return presses it. On
/// macOS 26 the background is a round Liquid Glass button instead, tinted for the same states.
final class ChromeButton: NSView {
    static let side = ChromeMetrics.button
    static let cornerRadius = ChromeMetrics.cornerRadius
    /// The glyph's opacity while disabled.
    static let disabledAlpha: CGFloat = 0.35
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
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled { hovered = false; pressed = false }
            setAccessibilityEnabled(isEnabled)
            stateChanged()
        }
    }

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
        focusRingType = .exterior
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

    private var shape: NSBezierPath { NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius) }

    override func draw(_ dirtyRect: NSRect) {
        if glass == nil, pressed || hovered {
            NSColor(hex: pressed ? theme.typeLight : theme.typeHyperLight).setFill()
            shape.fill()
        }
    }

    // MARK: Keyboard focus (Full Keyboard Access tabs through the revealed bars)

    override var acceptsFirstResponder: Bool { isEnabled && isShownInBar }
    override var canBecomeKeyView: Bool { acceptsFirstResponder }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { shape.fill() }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return super.becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return super.resignFirstResponder() }
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " || event.keyCode == 36 { press() } else { super.keyDown(with: event) }
    }

    /// Hidden bars (and hidden buttons) take no focus.
    private var isShownInBar: Bool {
        guard !isHiddenOrHasHiddenAncestor else { return false }
        var v: NSView? = superview
        while let view = v { if let bar = view as? HoverBar { return bar.isRevealed }; v = view.superview }
        return true
    }

    private func press() { if isEnabled { NSApp.sendAction(action, to: target, from: self) } }

    /// The glyph, in a child view so it sits above the glass.
    private func addGlyph() {
        let inset = (Self.side - ChromeIcon.size) / 2
        let view = GlyphView { [unowned self] rect in
            let tint = NSColor(hex: self.isPinned ? (self.hovered ? self.theme.accent3Secondary : self.theme.accent3Main)
                                                  : self.theme.typeMain).withAlphaComponent(self.isEnabled ? 1 : Self.disabledAlpha)
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

    override func mouseEntered(with event: NSEvent) { hovered = isEnabled }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseDown(with event: NSEvent) { pressed = isEnabled }
    override func mouseDragged(with event: NSEvent) { pressed = isEnabled && bounds.contains(convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) {
        let inside = pressed && bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        if inside { press() }
    }
    override func accessibilityPerformPress() -> Bool { press(); return isEnabled }
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

    /// How long the bar lingers after the pointer leaves it (time to reach chrome that belongs to it).
    var lingers: TimeInterval = 0
    /// Window points where hovering doesn't bring the bar up (the slot bar resting over it).
    var revealExcluded: ((NSPoint) -> Bool)?
    private var pointerInside = false
    private var held = false
    private var hideWork: DispatchWorkItem?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        pointerInside = true
        pointerMoved(event)
    }

    override func mouseMoved(with event: NSEvent) { pointerMoved(event) }

    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        hideUnlessHovered()
    }

    private func pointerMoved(_ event: NSEvent) {
        if !isRevealed, revealExcluded?(event.locationInWindow) == true { return }
        if let rest = restingSince, hypot(event.locationInWindow.x - rest.x, event.locationInWindow.y - rest.y) < 4 { return }
        restingSince = nil
        hideWork?.cancel()
        if !isRevealed { setRevealed(true, animated: true) }
    }

    /// Where the pointer rested when typing hid the bar; it stays down until the pointer really moves.
    private var restingSince: NSPoint?

    /// Typing in the note takes the bar down at once (it was covering the text), even with the pointer still over
    /// it; moving the pointer brings it back.
    func typingStarted(pointerAt point: NSPoint) {
        guard isRevealed, !pinnedVisible else { return }
        hideWork?.cancel()
        restingSince = point
        setRevealed(false, animated: true)
    }

    /// Keeps a revealed bar up while the pointer is on chrome that belongs to it (the slot bar above the bottom
    /// bar); it doesn't bring a hidden bar up.
    func hold(_ hold: Bool) {
        held = hold
        if hold { hideWork?.cancel() } else { hideUnlessHovered() }
    }

    private func hideUnlessHovered() {
        hideWork?.cancel()
        guard !pointerInside, !held, isRevealed, !pinnedVisible else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.pointerInside, !self.held else { return }
                self.setRevealed(self.pinnedVisible, animated: true)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + lingers, execute: work)
    }

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

/// Top strip: drags the window; on hover shows the traffic lights, then Settings, Search and Typing on the left
/// and New Note and Pin on the right, all on `ChromeMetrics`: the row is centred 20 pt from the top (the traffic
/// lights are moved onto it), the left group starts one gap after the zoom button, the right group ends 10 pt
/// from the edge, 8 pt between buttons. The strip is 35 pt tall, so it covers the buttons' lower edge.
final class TitleBarView: HoverBar {
    static let height = ChromeMetrics.topBarHeight
    /// Centre of the button row, from the window top.
    static let iconRow = ChromeMetrics.row

    let pinButton: ChromeButton
    /// The Typing options button; its menu drops from under it.
    let typingButton: ChromeButton
    private let buttons: [ChromeButton]

    init(target: AnyObject) {
        let settings = ChromeButton(.settings, "Settings", tooltip: "Settings - ⌘+,", target: target,
                                    action: #selector(Shell.openSettings(_:)))
        let search = ChromeButton(.search, "Search Notes", target: target, action: #selector(Shell.searchAllNotes(_:)))
        typingButton = ChromeButton(.typing, "Typing Options", tooltip: "Typing options", target: target,
                                    action: #selector(Shell.showTypingOptions(_:)))
        let new = ChromeButton(.new, "New Note", target: target, action: #selector(Shell.newNote(_:)))
        pinButton = ChromeButton(.pin, "Pin Super Notes to Top", target: target, action: #selector(Shell.togglePin(_:)))
        buttons = [settings, search, typingButton, new, pinButton]
        super.init(frame: .zero)
        buttons.forEach(content.addSubview)
        let step = ChromeMetrics.button + ChromeMetrics.spacing
        NSLayoutConstraint.activate([
            settings.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: ChromeMetrics.leadingInset),
            search.leadingAnchor.constraint(equalTo: settings.leadingAnchor, constant: step),
            typingButton.leadingAnchor.constraint(equalTo: search.leadingAnchor, constant: step),
            pinButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -ChromeMetrics.sideInset),
            new.trailingAnchor.constraint(equalTo: pinButton.trailingAnchor, constant: -step),
        ] + buttons.map { $0.centerYAnchor.constraint(equalTo: content.topAnchor, constant: Self.iconRow) })
    }
    required init?(coder: NSCoder) { fatalError() }

    /// In a window too narrow for both groups (under 261 pt) the Typing button gives way; its menu stays in the
    /// Edit menu's reach through Settings → Editor → Typing.
    override func layout() {
        super.layout()
        let fits = ChromeMetrics.leftButtonsFitting(width: bounds.width, left: 3, right: 2) == 3
        if typingButton.isHidden == fits { typingButton.isHidden = !fits }
    }

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

/// The Typing options menu, dropped from the top bar's Typing button: one checkmark item per `TypingOption` (the
/// checkers, a separator, then the substitutions), each applied to every editor the moment it's ticked and kept
/// in Settings → Editor → Typing. A greyed last line says what the shown note's mode suspends ("Code notes: no
/// checking or substitutions").
@MainActor
enum TypingMenu {
    static func build(mode: NoteMode, target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu(title: "Typing")
        menu.autoenablesItems = false
        for (i, option) in TypingOption.allCases.enumerated() {
            if i > 0, !option.isChecker, TypingOption.allCases[i - 1].isChecker { menu.addItem(.separator()) }
            let item = NSMenuItem(title: option.title, action: action, keyEquivalent: "")
            item.target = target
            item.tag = i
            item.state = option.isOn ? .on : .off
            item.toolTip = option.isSuspended(in: mode) ? "Not in \(mode.displayName.lowercased()) notes" : nil
            menu.addItem(item)
        }
        if let note = TypingOption.suspensionNote(for: mode) {
            menu.addItem(.separator())
            let item = NSMenuItem(title: note, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        return menu
    }

    /// Pops the menu up under `button`, 4 pt below it.
    static func show(mode: NoteMode, under button: NSView, target: AnyObject, action: Selector) {
        build(mode: mode, target: target, action: action).popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: button)
    }
}

/// Bottom strip (40 pt), shown on hover: Delete on the left; the note's date and position ("Oct 17, 2026 | 3 of
/// 12", the bar 8 pt from each part) in the middle, in the system's grey 11 pt subheadline; Previous / Next /
/// First and Export on the right. Buttons follow `ChromeMetrics`: 30 pt, centred 20 pt above the bottom, 10 pt
/// in from the sides and 8 pt apart. In a narrow window the text is cut short in the middle, then dropped, then
/// Export and First give way (`BottomBarLayout`), so nothing is clipped or overlapped. The shell keeps the bar
/// down while a mode owns the strip (Search's capsules, the find shelf).
final class BottomBarView: HoverBar {
    static let height = ChromeMetrics.bottomBarHeight
    static let textFont = NSFont.preferredFont(forTextStyle: .subheadline)
    private let info = NSTextField(labelWithString: "")
    private let delete: ChromeButton
    /// Previous, Next, First, Export: the right-hand group, in order.
    private let trailing: [ChromeButton]
    private let buttons: [ChromeButton]
    let exportButton: ChromeButton

    init(target: AnyObject) {
        delete = ChromeButton(.delete, "Delete Note", glass: .clear, target: target, action: #selector(Shell.moveToVoid(_:)))
        let previous = ChromeButton(.previous, "Previous Note", glass: .clear, target: target, action: #selector(Shell.previousNote(_:)))
        let next = ChromeButton(.next, "Next Note", glass: .clear, target: target, action: #selector(Shell.nextNote(_:)))
        let front = ChromeButton(.front, "Go to First Note", glass: .clear, target: target, action: #selector(Shell.goToFirstNote(_:)))
        exportButton = ChromeButton(.export, "Export", glass: .clear, target: target, action: #selector(Shell.exportFromBar(_:)))
        trailing = [previous, next, front, exportButton]
        buttons = [delete] + trailing
        super.init(frame: .zero)
        info.lineBreakMode = .byTruncatingMiddle
        info.identifier = NSUserInterfaceItemIdentifier("BottomBarInfo")
        // Placed by frame in `layout()`, from `BottomBarLayout.fit`.
        for view in buttons + [info] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = true
            content.addSubview(view)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let width = content.bounds.width, side = CGFloat(BottomBarLayout.button)
        let text = info.attributedStringValue.length == 0 ? 0 : ceil(info.cell?.cellSize.width ?? 0)   // with the cell's padding
        let fit = BottomBarLayout.fit(width: Double(width), textWidth: Double(text))
        let row = ChromeMetrics.row, y = row - side / 2
        let inset = CGFloat(BottomBarLayout.sideInset), step = side + CGFloat(BottomBarLayout.spacing)
        delete.frame = NSRect(x: inset, y: y, width: side, height: side)
        let shown = Array(trailing.prefix(fit.buttons - 1))
        for button in trailing { button.isHidden = !shown.contains { $0 === button } }
        for (i, button) in shown.reversed().enumerated() {
            button.frame = NSRect(x: width - inset - side - CGFloat(i) * step, y: y, width: side, height: side)
        }
        // The text sits centred between Delete and Previous, at least 8 pt from each.
        info.isHidden = fit.textWidth == 0
        guard let left = shown.first?.frame.minX, !info.isHidden else { return }
        let gap = CGFloat(BottomBarLayout.spacing), textWidth = CGFloat(fit.textWidth)
        let lo = delete.frame.maxX + gap, hi = left - gap - textWidth
        let height = info.fittingSize.height
        info.frame = NSRect(x: min(max((delete.frame.maxX + left - textWidth) / 2, lo), hi), y: row - height / 2,
                            width: textWidth, height: height)
    }

    override func setRevealed(_ revealed: Bool, animated: Bool) {
        if revealed { buttons.filter { $0 !== exportButton }.forEach { $0.refreshTooltip() } }
        super.setRevealed(revealed, animated: animated)
    }

    /// `parts` are the note's date and position ("Oct 17, 2026", "3 of 12", …), shown with "|" between them.
    func update(parts: [String], theme: Theme) {
        let text = NSMutableAttributedString()
        let gap = CGFloat(BottomBarLayout.spacing)
        for (i, part) in parts.enumerated() {
            if i > 0, text.length > 0 {
                // 8 pt either side of the bar: kerning after the previous part's last character and after the bar.
                text.addAttribute(.kern, value: gap, range: NSRange(location: text.length - 1, length: 1))
                text.append(NSAttributedString(string: "|", attributes: [.kern: gap]))
            }
            text.append(NSAttributedString(string: part))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        text.addAttributes([.font: Self.textFont, .foregroundColor: NSColor.systemGray, .paragraphStyle: paragraph],
                           range: NSRange(location: 0, length: text.length))
        if !info.attributedStringValue.isEqual(to: text) {
            info.attributedStringValue = text
            needsLayout = true
        }
        buttons.forEach { $0.theme = theme }
    }
}

/// The slot bar: a floating capsule of the nine planets (Mercury … Pluto), 32 pt tall with 16 pt side padding,
/// planets in 22 pt frames 3 pt apart. The capsule is the theme background with a hairline grey border and a faint
/// accent glow (Liquid Glass tinted with the background on macOS 26); the planets sit in their own layer above it
/// so they stay crisp. The open slot is `accent1Main` in a 28 pt frame scaled 1.18; slots holding a note are
/// filled, empty slots are faint outlines; the planet under the pointer darkens and a tip above it names the
/// slot's note (or says how to fill it). A click opens the slot (or puts the current note in an empty one); a
/// right-click offers the slot's actions. When it shows is `SlotBarVisibility`'s call (fade 150 ms).
final class SlotsBarView: NSView {
    static let height: CGFloat = 32
    static let bottomInset: CGFloat = 10
    static let openPlanetScale: CGFloat = 1.18
    static let fadeDuration: TimeInterval = SlotBarVisibility.fadeDuration
    var onSelect: ((Int) -> Void)?
    /// The menu for a right-click on `slot`.
    var contextMenu: ((Int) -> NSMenu?)?
    /// Called when the pointer comes onto the shown bar or leaves it (the bottom bar stays up meanwhile).
    var onHoverChange: ((Bool) -> Void)?
    /// Fades the bar in or out; a hidden bar lets clicks through to the note.
    var isShown = false {
        didSet {
            guard isShown != oldValue else { return }
            NSAnimationContext.runAnimationGroup { $0.duration = Self.fadeDuration; animator().alphaValue = isShown ? 1 : 0 }
            if !isShown { pointerLeft() }
        }
    }
    private var titles: [Int: String] = [:]
    private var open: Int?
    private var theme: Theme = .defaultLight
    private var glass: NSView?
    private let planets = PlanetsView()
    private let tip = SlotTipView()
    private(set) var hovered: Int?
    private var pointerOver = false
    /// A label shown above a planet for a moment ("Slot 3 · Groceries" as it opens); the pointer's tip takes over.
    private var announcement: (slot: Int, text: String)?
    private var announceWork: DispatchWorkItem?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        alphaValue = 0
        layer?.masksToBounds = false
        layer?.cornerRadius = Self.height / 2
        if #available(macOS 26, *) {
            let g = NSGlassEffectView()
            g.cornerRadius = Self.height / 2
            addSubview(g)
            glass = g
        } else {
            layer?.borderWidth = 1
            layer?.shadowRadius = 7
            layer?.shadowOffset = .zero
            layer?.shadowOpacity = 0.2
        }
        addSubview(planets)   // above the glass, never blurred by it
        tip.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize { NSSize(width: SlotBarLayout.width(open: open), height: Self.height) }

    /// The tip floats above the bar, over the note, so it lives in the bar's superview.
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        tip.removeFromSuperview()
        superview?.addSubview(tip, positioned: .above, relativeTo: self)
    }

    /// `titles[slot]` is the occupant's title; `open` is the slot shown (nil = the ephemeral deck).
    func update(titles: [Int: String], open: Int?, theme: Theme) {
        self.titles = titles
        if open != self.open { invalidateIntrinsicContentSize(); needsLayout = true }
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
        planets.states = SlotBarLayout.states(occupied: Set(titles.keys), open: open)
        planets.open = open
        planets.theme = theme
        tip.theme = theme
        if let shown = hovered ?? announcement?.slot { showTip(for: shown) }
    }

    /// Shows `text` above `slot`'s planet for `SlotBarVisibility.navigationLinger` (what just happened there), unless
    /// the pointer is on a planet, whose tip comes first.
    func announce(_ text: String, at slot: Int) {
        announceWork?.cancel()
        announcement = (slot, text)
        if hovered == nil { showTip(for: slot) }
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.endAnnouncement() } }
        announceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + SlotBarVisibility.navigationLinger, execute: work)
    }

    private func endAnnouncement() {
        announceWork?.cancel()
        announceWork = nil
        guard announcement != nil else { return }
        announcement = nil
        if let hovered { showTip(for: hovered) } else { tip.isHidden = true }
    }

    /// A window too narrow for the whole bar shrinks it evenly (its contents are laid out at full size in the
    /// bounds, which scale to the frame).
    override func layout() {
        let natural = CGFloat(SlotBarLayout.width(open: open))
        let scale = frame.width > 0 ? min(1, frame.width / natural) : 1
        let size = NSSize(width: frame.width / scale, height: frame.height / scale)
        if bounds.size != size { setBoundsSize(size) }
        glass?.frame = bounds
        planets.frame = bounds
        super.layout()
        if let shown = hovered ?? announcement?.slot { showTip(for: shown) }
    }

    // MARK: Pointer

    override func hitTest(_ point: NSPoint) -> NSView? { isShown && frame.contains(point) ? self : nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        guard isShown else { return }
        pointerOver = true
        onHoverChange?(true)
        pointerMoved(event)
    }

    override func mouseMoved(with event: NSEvent) { pointerMoved(event) }

    override func mouseExited(with event: NSEvent) { pointerLeft() }

    private func pointerLeft() {
        setHovered(nil)
        if !isShown { endAnnouncement() }
        guard pointerOver else { return }
        pointerOver = false
        onHoverChange?(false)
    }

    /// The click is the bar's (nothing behind it, the window included, sees the press).
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard isShown, bounds.contains(p), let slot = SlotBarLayout.slot(atX: Double(p.x), open: open) else { return }
        onSelect?(slot)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        guard isShown, bounds.contains(p), let slot = SlotBarLayout.slot(atX: Double(p.x), open: open) else { return nil }
        return contextMenu?(slot)
    }

    private func pointerMoved(_ event: NSEvent) {
        guard isShown else { return setHovered(nil) }
        let p = convert(event.locationInWindow, from: nil)
        setHovered(bounds.contains(p) ? SlotBarLayout.slot(atX: Double(p.x), open: open) : nil)
    }

    /// Marks `slot` as under the pointer (offscreen renders call this directly).
    func setHovered(_ slot: Int?) {
        guard slot != hovered || (slot != nil && tip.isHidden) else { return }
        hovered = slot
        planets.hovered = slot
        if slot != nil { announcement = nil; announceWork?.cancel() }
        if let slot { showTip(for: slot) } else { tip.isHidden = true }
    }

    /// Puts the tip (or the announcement) 6 pt above `slot`'s planet, inside the window.
    private func showTip(for slot: Int) {
        guard let container = superview else { return }
        if let announcement, announcement.slot == slot, hovered == nil {
            tip.text = announcement.text
        } else {
            let opens = ChromeTooltip.shortcut(action: #selector(Shell.openSlotItem(_:)), tag: slot)
            let assign = ChromeTooltip.shortcut(action: #selector(Shell.assignSlotItem(_:)), tag: slot)
            tip.text = SlotBarLayout.tip(slot: slot, title: titles[slot], isOpen: slot == open, openShortcut: opens, assignShortcut: assign)
        }
        let size = tip.fittingSize(maxWidth: container.bounds.width - 16)
        let column = convert(NSRect(x: SlotBarLayout.x(of: slot, open: open), y: 0,
                                    width: SlotBarLayout.frames(open: open)[slot], height: bounds.height), to: container)
        let x = min(max(column.midX - size.width / 2, 8), container.bounds.width - size.width - 8)
        let y = container.isFlipped ? column.minY - 6 - size.height : column.maxY + 6
        tip.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        tip.isHidden = false
    }
}

/// The nine planets, drawn above the slot bar's capsule; it never takes the mouse (the bar does).
private final class PlanetsView: NSView {
    var states: [SlotBarLayout.State] = [] { didSet { needsDisplay = true } }
    var open: Int? { didSet { needsDisplay = true } }
    var hovered: Int? { didSet { needsDisplay = true } }
    var theme: Theme = .defaultLight { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let main = NSColor(hex: theme.typeMain), light = NSColor(hex: theme.typeLight)
        for planet in Planet.allCases {
            let slot = planet.rawValue
            let state = states.indices.contains(slot) ? states[slot] : .empty
            let width = CGFloat(SlotBarLayout.frames(open: open)[slot])
            let side = width * (state == .open ? SlotsBarView.openPlanetScale : 1)
            let midX = CGFloat(SlotBarLayout.x(of: slot, open: open)) + width / 2
            let rect = NSRect(x: midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
            let hot = slot == hovered
            let color: NSColor = switch state {
            case .open: NSColor(hex: theme.accent1Main)
            case .filled: hot ? main : main.withAlphaComponent(0.55)
            case .empty: hot ? main.withAlphaComponent(0.7) : light
            }
            planet.draw(in: rect, color: color, outlined: state == .empty)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The slot bar's hover tip: one or two lines of system 11 pt text in `typeReverse` on a `typeMain` rounded
/// rectangle (the message pill's colours), padded 10 × 5 pt.
private final class SlotTipView: NSView {
    var text = "" { didSet { needsDisplay = true } }
    var theme: Theme = .defaultLight { didSet { needsDisplay = true } }
    private static let padding = NSSize(width: 10, height: 5)
    override var isFlipped: Bool { true }

    private var attributed: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 1
        paragraph.lineBreakMode = .byTruncatingTail
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor(hex: theme.typeReverse),
            .paragraphStyle: paragraph,
        ])
    }

    func fittingSize(maxWidth: CGFloat) -> NSSize {
        let bounds = attributed.boundingRect(with: NSSize(width: maxWidth - 2 * Self.padding.width, height: 100),
                                             options: [.usesLineFragmentOrigin])
        return NSSize(width: ceil(bounds.width) + 2 * Self.padding.width, height: ceil(bounds.height) + 2 * Self.padding.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(hex: theme.typeMain).setFill()
        let radius = min(8, bounds.height / 2)
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        attributed.draw(with: bounds.insetBy(dx: Self.padding.width, dy: Self.padding.height), options: [.usesLineFragmentOrigin])
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The window's content view: it reports where the pointer is over the window (the slot bar comes up when the
/// pointer rests along the bottom).
final class RootView: NSView {
    /// The pointer's position in this view's coordinates, nil once it has left the window.
    var onPointer: ((NSPoint?) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onPointer?(convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { onPointer?(convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { onPointer?(nil) }
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

    /// The note's text view (the editor's scroll view's document).
    var textView: NSTextView? {
        editor.view.subviews.lazy.compactMap { $0 as? NSScrollView }.first?.documentView as? NSTextView
    }

    /// The caret (or selection), carried over when a note changes panes so it never jumps.
    var selection: NSRange? {
        get { textView?.selectedRange() }
        set {
            guard let newValue, let textView else { return }
            let length = (textView.string as NSString).length
            let location = min(newValue.location, length)
            textView.setSelectedRange(NSRange(location: location, length: min(newValue.length, length - location)))
            textView.scrollRangeToVisible(textView.selectedRange())
        }
    }

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
