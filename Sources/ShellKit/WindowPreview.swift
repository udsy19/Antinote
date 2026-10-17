import AppKit

/// The main note window built offscreen for rendering (JotterRender); it is never shown. Notes come from
/// `Services.store` (front note first), so the caller seeds the store before asking.
public enum WindowPreview {
    /// The main window's default content size.
    @MainActor public static var defaultSize: NSSize { MainWindow.defaultSize }

    /// The window's whole frame view (traffic lights included). `revealed` shows the hover-only bars.
    @MainActor public static func frameView(revealed: Bool, slot: Int? = nil) -> NSView {
        Shell.shared.prepareForPreview(revealed: revealed, slot: slot)
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
