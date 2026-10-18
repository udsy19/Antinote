import AppKit
import SuperNotesCore

/// The main note window built offscreen for rendering (SuperNotesRender); it is never shown. Notes come from
/// `Services.store` (front note first), so the caller seeds the store before asking.
public enum WindowPreview {
    /// The main window's default content size.
    @MainActor public static var defaultSize: NSSize { MainWindow.defaultSize }

    /// What the slot bar is doing in a render: as the shell's rules leave it, up because the pointer has rested
    /// along the bottom, down because a keystroke just went into the note, or reset to its hidden start.
    public enum SlotBar: Sendable { case natural, hovering, typing, hidden }

    /// The window's whole frame view (traffic lights included) at content `size` (the default when nil).
    /// `revealed` shows the hover-only bars; `hoveredSlot` rests the pointer on that planet of the slot bar;
    /// `presenting` shows a view over the note area (Search), nil takes any presented view down.
    @MainActor public static func frameView(revealed: Bool, slot: Int? = nil, size: NSSize? = nil, hoveredSlot: Int? = nil,
                                            slotBar: SlotBar = .natural, presenting: NSView? = nil) -> NSView {
        Shell.shared.prepareForPreview(revealed: revealed, slot: slot, size: size, hoveredSlot: hoveredSlot, slotBar: slotBar,
                                       presenting: presenting)
    }

    /// An editor command on the shown note (`.find` docks the find shelf).
    @MainActor public static func perform(_ command: EditorCommand) { Shell.shared.performForPreview(command) }

    /// The Typing button's frame in the frame view, and a facsimile of its menu (an `NSMenu` can't be drawn
    /// offscreen) with the items and checkmarks `TypingMenu` would show for a note of `mode`.
    @MainActor public static var typingButtonFrame: NSRect { Shell.shared.typingButtonFrameInFrame }
    @MainActor public static func typingMenuFacsimile(mode: NoteMode) -> NSView {
        MenuFacsimileView(menu: TypingMenu.build(mode: mode, target: Shell.shared, action: #selector(Shell.toggleTypingOption(_:))))
    }

    /// The offscreen window itself (its first responder is the shown note's text view) and the note it shows,
    /// for self-tests that drive the shell's menu actions.
    @MainActor public static var window: NSWindow { Shell.shared.window }
    @MainActor public static var currentNoteID: UUID? { Shell.shared.currentNoteID }
    /// The menu bar as built for the preview window.
    @MainActor public static var mainMenu: NSMenu? { MainMenu.buildForPreview(); return MainMenu.built }
    /// File › Delete Note on the shown note (the confirmation is skipped when its warning is suppressed).
    @MainActor public static func deleteCurrentNote() { Shell.shared.moveToVoid(nil) }
    /// Points the already-built window at the notes now in `Services.store` (self-tests that swap the store).
    @MainActor public static func reload() { Shell.shared.reloadForPreview() }
    /// Whether the slot bar is up right now.
    @MainActor public static var isSlotBarShown: Bool { Shell.shared.isSlotBarShown }
    /// The slot in front (nil = the deck).
    @MainActor public static var openSlot: Int? { Shell.shared.shownSlot }
    /// A swipe or ⌘[ / ⌘]: through the deck, or the slots in use while a slot is in front.
    @MainActor public static func navigate(_ direction: SwipeDirection) { Shell.shared.navigate(direction) }
    /// The Navigate menu's slot actions.
    @MainActor public static func openSlot(_ slot: Int) { Shell.shared.openSlot(slot) }
    @MainActor public static func backToNotes() { Shell.shared.goToDeck(nil) }
    @MainActor public static func putInSlot(_ slot: Int) { Shell.shared.assign(toSlot: slot) }
    @MainActor public static func removeFromSlot() { Shell.shared.removeFromSlot(nil) }
    /// Whether Esc would go back to the deck right now (the hidden Esc menu item's validation).
    @MainActor public static var escapeGoesBack: Bool { Shell.shared.escapeMeansBack }

    /// The slot bar alone on a strip of the note's background `width` wide: `titles[slot]` for the slots holding
    /// notes, `open` the slot shown, the pointer on `hovered` (its tip above the bar).
    @MainActor public static func slotsBar(titles: [Int: String], open: Int?, hovered: Int?, width: CGFloat) -> NSView {
        MainMenu.buildForPreview()   // the empty slots' tip names the Assign to Slot shortcut
        let theme = Theme.current
        let strip = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 96))
        strip.wantsLayer = true
        strip.layer?.backgroundColor = NSColor(hex: theme.background).cgColor
        let bar = SlotsBarView()
        bar.update(titles: titles, open: open, theme: theme)
        bar.isShown = true
        bar.alphaValue = 1
        let size = bar.intrinsicContentSize
        bar.frame = NSRect(x: ((width - size.width) / 2).rounded(), y: SlotsBarView.bottomInset, width: size.width, height: size.height)
        strip.addSubview(bar)
        bar.layoutSubtreeIfNeeded()
        bar.setHovered(hovered)
        return strip
    }
}

extension WindowPreview {
    /// The chrome glyphs and planets, each drawn on its full 30 pt design canvas in black on white (for comparing
    /// against reference artwork), keyed by name.
    @MainActor public static func glyphs() -> [(name: String, view: NSView)] {
        let icons: [(String, ChromeIcon)] = [("settings", .settings), ("search", .search), ("typing", .typing), ("new", .new), ("pin", .pin),
                                             ("previous", .previous), ("next", .next), ("front", .front),
                                             ("export", .export), ("delete", .delete)]
        var out = icons.map { name, icon in
            ("icon-" + name, CanvasView { rect in
                let image = icon.image
                let full = NSImage(size: rect.size, flipped: false) { r in
                    image.draw(in: r)
                    NSColor.black.set()
                    r.fill(using: .sourceAtop)
                    return true
                }
                full.draw(in: rect)
            } as NSView)
        }
        out += Planet.allCases.map { planet in
            ("planet-" + planet.name.lowercased(), CanvasView(flipped: true) { rect in planet.draw(in: rect, color: .black) } as NSView)
        }
        return out
    }
}

/// White square that draws its content with a closure.
private final class CanvasView: NSView {
    private let drawing: (NSRect) -> Void
    private let flippedCanvas: Bool
    init(flipped: Bool = false, _ drawing: @escaping (NSRect) -> Void) {
        self.drawing = drawing
        flippedCanvas = flipped
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { flippedCanvas }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        drawing(bounds)
    }
}

/// Draws an `NSMenu` the way the system shows it, near enough for a render: 13 pt system text, checkmarks for
/// ticked items, hairline separators, greyed disabled lines, on a rounded `windowBackgroundColor` panel.
private final class MenuFacsimileView: NSView {
    private let items: [NSMenuItem]
    static let width: CGFloat = 272
    static let rowHeight: CGFloat = 22
    static let separatorHeight: CGFloat = 11
    static let padding: CGFloat = 5

    init(menu: NSMenu) {
        items = menu.items
        super.init(frame: .zero)
        let height = items.reduce(2 * Self.padding) { $0 + ($1.isSeparatorItem ? Self.separatorHeight : Self.rowHeight) }
        frame = NSRect(x: 0, y: 0, width: Self.width, height: height)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let panel = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSColor.windowBackgroundColor.setFill()
        panel.fill()
        NSColor.separatorColor.setStroke()
        panel.lineWidth = 1
        panel.stroke()
        var y = Self.padding
        let font = NSFont.menuFont(ofSize: 13)
        for item in items {
            if item.isSeparatorItem {
                NSColor.separatorColor.setFill()
                NSRect(x: 10, y: y + Self.separatorHeight / 2, width: bounds.width - 20, height: 1).fill()
                y += Self.separatorHeight
                continue
            }
            let color: NSColor = item.isEnabled ? .labelColor : .tertiaryLabelColor
            if item.state == .on {
                ("✓" as NSString).draw(at: NSPoint(x: 9, y: y + 3), withAttributes: [.font: font, .foregroundColor: color])
            }
            (item.title as NSString).draw(at: NSPoint(x: 24, y: y + 3), withAttributes: [.font: font, .foregroundColor: color])
            y += Self.rowHeight
        }
    }
}
