import AppKit
import SuperNotesCore

/// Registers this module's services in `Services` (called once at launch).
public enum ToolsKitModule {
    @MainActor private static var urlHandler: URLSchemeHandler?

    @MainActor public static func install() {
        Services.timers = TimerManager()
        Services.export = ExportManager()
        Services.panels = ToolsPanels()
        let handler = URLSchemeHandler()
        handler.install()
        urlHandler = handler
    }
}
