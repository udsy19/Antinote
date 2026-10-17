import AppKit
import JotterCore

/// Registers this module's services in `Services` (called once at launch).
public enum NoteEngineModule {
    @MainActor public static func install() {
        Services.analyzer = NoteEngine()
        RatesProvider.shared.start()
    }
}
