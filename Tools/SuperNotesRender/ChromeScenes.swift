import AppKit
import ShellKit

/// The chrome glyphs and planets on their 30 pt design canvas, one scene each.
@MainActor
extension Scenes {
    static var chromeGlyphs: [Scene] {
        WindowPreview.glyphs().map { glyph in
            Scene(name: "glyph-" + glyph.name, size: NSSize(width: 30, height: 30)) { glyph.view }
        }
    }
}
