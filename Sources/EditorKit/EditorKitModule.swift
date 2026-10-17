import AppKit
import JotterCore

/// Registers this module's services in `Services` (called once at launch).
public enum EditorKitModule {
    @MainActor public static func install() {
        Services.editorFactory = JotterEditorFactory()
    }
}
