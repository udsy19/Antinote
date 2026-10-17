import AppKit
import JotterCore

/// Registers this module's services in `Services` (called once at launch).
public enum ExtensionsKitModule {
    @MainActor public static func install() {
        Services.extensions = ExtensionsManager()
    }
}
