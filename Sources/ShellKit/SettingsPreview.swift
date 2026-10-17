import AppKit
import SwiftUI

/// Offscreen Settings windows for rendering (SuperNotesRender). The window is never shown.
public enum SettingsPreview {
    /// A Settings window showing `tab` (a `SettingsTab` id or title).
    @MainActor public static func window(tab: String) -> NSWindow {
        MainMenu.buildForPreview()
        let (window, controller) = SettingsWindow.makeWindow(autosave: false)
        controller.selectedTabViewItemIndex = SettingsTab(routing: tab).flatMap { SettingsTab.allCases.firstIndex(of: $0) } ?? 0
        return window
    }

    /// One tab's form alone, `height` points tall, so every section shows (the window only shows the top).
    @MainActor public static func page(tab: String, height: CGFloat) -> NSView {
        MainMenu.buildForPreview()
        let page = SettingsWindow.page(SettingsTab(routing: tab) ?? .general)
        let view = NSHostingView(rootView: page.frame(width: SettingsWindow.contentSize.width, height: height))
        view.frame = NSRect(x: 0, y: 0, width: SettingsWindow.contentSize.width, height: height)
        return view
    }
}
