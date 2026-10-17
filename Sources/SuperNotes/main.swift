import AppKit
import SuperNotesCore
import StorageKit
import NoteEngine
import ExtensionsKit
import EditorKit
import ShellKit
import ToolsKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Order matters: storage and the engine first, then extensions and the editor, the shell last.
        StorageKitModule.install()
        NoteEngineModule.install()
        ExtensionsKitModule.install()
        EditorKitModule.install()
        ToolsKitModule.install()
        ShellKitModule.install()
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
