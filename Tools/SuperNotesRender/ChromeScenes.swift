import AppKit
import SuperNotesCore
import ShellKit
import ToolsKit

/// The chrome glyphs and planets on their 30 pt design canvas, one scene each.
@MainActor
extension Scenes {
    static var chromeGlyphs: [Scene] {
        WindowPreview.glyphs().map { glyph in
            Scene(name: "glyph-" + glyph.name, size: NSSize(width: 30, height: 30)) { glyph.view }
        }
    }

    /// The window chrome in every mode that owns the bottom strip: the Typing menu open under its button, Search
    /// (list, cards, Select) inside the window at the minimum, default and a very wide size, the find shelf.
    static var chrome: [Scene] {
        let size = WindowPreview.defaultSize
        let wide = NSSize(width: 1200, height: 700), narrow = NSSize(width: 240, height: 400)
        func search(cards: Bool = false, selecting: Bool = false) -> NSView {
            ToolsPreviews.search(notes: SearchDemo.notes, cards: cards, selecting: selecting, now: SearchDemo.now)
        }
        return [
            Scene(name: "window-typing-menu", size: size) { typingMenuFrame() },
            Scene(name: "window-typing-menu-dark", size: size, dark: true) { typingMenuFrame() },
            Scene(name: "window-search-list-350", size: size) { windowFrame(revealed: true, presenting: search()) },
            Scene(name: "window-search-list-350-dark", size: size, dark: true) { windowFrame(revealed: true, presenting: search()) },
            Scene(name: "window-search-cards-350", size: size) { windowFrame(revealed: true, presenting: search(cards: true)) },
            Scene(name: "window-search-select-350", size: size) { windowFrame(revealed: true, presenting: search(selecting: true)) },
            Scene(name: "window-search-list-240", size: narrow) { windowFrame(revealed: true, size: narrow, presenting: search()) },
            Scene(name: "window-search-list-1200", size: wide) { windowFrame(revealed: true, size: wide, presenting: search()) },
            Scene(name: "window-search-cards-1200", size: wide) { windowFrame(revealed: true, size: wide, presenting: search(cards: true)) },
            Scene(name: "window-search-cards-1200-dark", size: wide, dark: true) {
                windowFrame(revealed: true, size: wide, presenting: search(cards: true))
            },
            Scene(name: "window-find-shelf", size: size) { findShelfFrame() },
            Scene(name: "window-find-shelf-1200", size: wide) { findShelfFrame(size: wide) },
        ]
    }

    /// The note window with the hover bars up and the Typing menu (a facsimile) dropped from its button.
    private static func typingMenuFrame() -> NSView {
        let frame = windowFrame(revealed: true)
        let size = WindowPreview.window.contentView!.superview!.bounds.size
        frame.frame = NSRect(origin: .zero, size: size)
        let container = NSView(frame: frame.frame)
        container.addSubview(frame)
        let menu = WindowPreview.typingMenuFacsimile(mode: .math)
        let button = WindowPreview.typingButtonFrame
        // Like the system, the menu shifts left rather than run off the window.
        menu.frame.origin = NSPoint(x: min(button.minX, size.width - menu.frame.width - 6), y: button.minY - 4 - menu.frame.height)
        container.addSubview(menu)
        return container
    }

    /// The note with ⌘F's shelf docked at the bottom: the bottom bar stays down (the pointer is there, but the
    /// shelf owns the strip).
    private static func findShelfFrame(size: NSSize? = nil) -> NSView {
        _ = windowFrame(revealed: true, size: size)
        WindowPreview.perform(.find)
        let frame = windowFrame(revealed: true, size: size)
        // The next scene starts without the shelf: its Done button closes it.
        if let done = buttons(in: WindowPreview.window.contentView!).first(where: { $0.title == "Done" }) { done.performClick(nil) }
        return frame
    }

    private static func buttons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
    }
}
