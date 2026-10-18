import AppKit
import SuperNotesCore

/// Registers this module's service in `Services` (called once at launch). The background model download is
/// scheduled once the app has finished launching.
public enum AIKitModule {
    @MainActor public static func install() {
        Services.ai = AIService.shared
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { AIService.shared.start() }
        }
    }
}
