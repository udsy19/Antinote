import AppKit
import SuperNotesCore

/// Registers this module's services in `Services` (called once at launch).
public enum ShellKitModule {
    @MainActor public static func install() {
        let shell = Shell.shared
        Services.windows = shell
        NSApp.mainMenu = MainMenu.build(target: shell)
        if !Defaults[.restorePinState] { Defaults[.pinOnTop] = false }
        Presence.shared.applyActivationPolicy()
        // The app delegate only calls `install()` (in applicationWillFinishLaunching); everything that needs
        // the other modules' services or a finished launch happens once launching completes.
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { shell.launch() }
        }
    }
}

// Module-private state.
extension Defaults.Keys {
    static let shellKitCurrentNote = Key<String>("shellKitCurrentNote", default: "")
    /// Seconds since 1970 when the main window was last hidden (drives `newNoteAfterMinutes`).
    static let shellKitLastHidden = Key<Double>("shellKitLastHidden", default: 0)
    static let shellKitSplit = Key<Bool>("shellKitSplit", default: false)
    static let shellKitSplitHorizontal = Key<Bool>("shellKitSplitHorizontal", default: false)
    static let shellKitSwapPanes = Key<Bool>("shellKitSwapPanes", default: false)
    static let shellKitNewNotesInEphemeral = Key<Bool>("shellKitNewNotesInEphemeral", default: true)
}
