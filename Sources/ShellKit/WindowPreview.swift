import AppKit
import SuperNotesCore

/// The main note window built offscreen for rendering (SuperNotesRender); it is never shown. Notes come from
/// `Services.store` (front note first), so the caller seeds the store before asking.
public enum WindowPreview {
    /// The main window's default content size.
    @MainActor public static var defaultSize: NSSize { MainWindow.defaultSize }

    /// The window's whole frame view (traffic lights included) at content `size` (the default when nil).
    /// `revealed` shows the hover-only bars; `hoveredSlot` rests the pointer on that planet of the slot bar.
    @MainActor public static func frameView(revealed: Bool, slot: Int? = nil, size: NSSize? = nil, hoveredSlot: Int? = nil) -> NSView {
        Shell.shared.prepareForPreview(revealed: revealed, slot: slot, size: size, hoveredSlot: hoveredSlot)
    }

    /// The offscreen window itself (its first responder is the shown note's text view) and the note it shows,
    /// for self-tests that drive the shell's menu actions.
    @MainActor public static var window: NSWindow { Shell.shared.window }
    @MainActor public static var currentNoteID: UUID? { Shell.shared.currentNoteID }
    /// The menu bar as built for the preview window.
    @MainActor public static var mainMenu: NSMenu? { MainMenu.buildForPreview(); return MainMenu.built }
    /// File › Delete Note on the shown note (the confirmation is skipped when its warning is suppressed).
    @MainActor public static func deleteCurrentNote() { Shell.shared.moveToVoid(nil) }

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
        let icons: [(String, ChromeIcon)] = [("settings", .settings), ("search", .search), ("new", .new), ("pin", .pin),
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
