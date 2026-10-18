import AppKit
import SuperNotesCore
import ShellKit

/// Settings window scenes: every tab in light mode plus one tab in dark mode. The whole window frame (title and
/// toolbar included) is captured from an offscreen Settings window and shown as an image.
@MainActor
extension Scenes {
    static var settings: [Scene] {
        let size = SettingsPreview.window(tab: "general").frame.size
        let tabs = ["general", "appearance", "editor", "notes", "keywords", "shortcuts", "timer", "export",
                    "extensions", "ai", "privacy", "updates"]
        return tabs.map { tab in Scene(name: "settings-\(tab)", size: size) { settingsWindow(tab) } }
            + [Scene(name: "settings-notes-dark", size: size, dark: true) { settingsWindow("notes") }]
            + tabs.map { tab in
                let height = fullHeights[tab] ?? 1100
                return Scene(name: "settings-full-\(tab)", size: NSSize(width: size.width, height: height)) {
                    snapshot(SettingsPreview.page(tab: tab, height: height))
                }
            }
            + [Scene(name: "settings-shortcuts-rebound", size: NSSize(width: size.width, height: 900)) { reboundShortcuts() }]
    }

    /// Shortcuts with "Create New Note" moved to ⌥⌘N and "Delete Note" left without a shortcut.
    private static func reboundShortcuts() -> NSView {
        let none: Shortcut? = nil
        Defaults[.menuShortcuts] = ["newNote": Shortcut(keyEquivalent: "n", modifiers: [.command, .option]), "moveToVoid": none]
        defer { Defaults.reset(.menuShortcuts) }
        return snapshot(SettingsPreview.page(tab: "shortcuts", height: 900))
    }

    /// Tall enough to show every section of each tab.
    private static let fullHeights: [String: CGFloat] = [
        "appearance": 2350, "editor": 2000, "notes": 1600, "keywords": 3000, "privacy": 1100, "general": 1250,
        "shortcuts": 2600, "timer": 1100, "export": 1100, "ai": 900,
    ]

    private static func settingsWindow(_ tab: String) -> NSView {
        let window = SettingsPreview.window(tab: tab)
        let frame = window.contentView?.superview ?? window.contentView!
        frame.layoutSubtreeIfNeeded()
        return snapshot(frame)
    }
}
