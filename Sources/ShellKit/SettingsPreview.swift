import AppKit

/// Offscreen Settings windows for rendering (JotterRender). The window is never shown.
public enum SettingsPreview {
    /// A Settings window showing `tab` (a `SettingsTab` id or title).
    @MainActor public static func window(tab: String) -> NSWindow {
        let (window, controller) = SettingsWindow.makeWindow(autosave: false)
        controller.selectedTabViewItemIndex = SettingsTab(routing: tab).flatMap { SettingsTab.allCases.firstIndex(of: $0) } ?? 0
        return window
    }
}
