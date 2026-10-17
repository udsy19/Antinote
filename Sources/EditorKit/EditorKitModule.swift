import AppKit
import SuperNotesCore

/// Registers this module's services in `Services` (called once at launch).
public enum EditorKitModule {
    @MainActor public static func install() {
        Services.editorFactory = SuperNotesEditorFactory()
    }
}
