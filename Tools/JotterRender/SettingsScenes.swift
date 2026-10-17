import AppKit
import JotterCore
import ShellKit

/// Settings window scenes: every tab in light mode plus one tab in dark mode. The whole window frame (title and
/// toolbar included) is captured from an offscreen Settings window and shown as an image.
@MainActor
extension Scenes {
    static var settings: [Scene] {
        let size = SettingsPreview.window(tab: "general").frame.size
        let tabs = ["general", "appearance", "editor", "notes", "keywords", "shortcuts", "timer", "export",
                    "extensions", "privacy", "updates"]
        return tabs.map { tab in Scene(name: "settings-\(tab)", size: size) { settingsWindow(tab) } }
            + [Scene(name: "settings-notes-dark", size: size, dark: true) { settingsWindow("notes") }]
            + tabs.map { tab in
                let height = fullHeights[tab] ?? 1100
                return Scene(name: "settings-full-\(tab)", size: NSSize(width: size.width, height: height)) {
                    snapshot(SettingsPreview.page(tab: tab, height: height))
                }
            }
    }

    /// Tall enough to show every section of each tab.
    private static let fullHeights: [String: CGFloat] = [
        "appearance": 1900, "editor": 1900, "notes": 1600, "keywords": 3300, "privacy": 1100, "general": 1250,
    ]

    private static func settingsWindow(_ tab: String) -> NSView {
        let window = SettingsPreview.window(tab: tab)
        let frame = window.contentView?.superview ?? window.contentView!
        frame.layoutSubtreeIfNeeded()
        return snapshot(frame)
    }
}
