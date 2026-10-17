import AppKit
import SuperNotesCore

extension Defaults.Keys {
    static let storageLastAutoBackup = Key<Date>("storageKit.lastAutoBackup", default: .distantPast)
}

/// Registers this module's services in `Services` (called once at launch).
public enum StorageKitModule {
    @MainActor private static var maintenance: Timer?

    @MainActor public static func install() {
        LegacyMigration.run()   // before the store opens: brings over notes, settings and keys from before the rename
        let store: SQLiteNoteStore
        do {
            store = try SQLiteNoteStore()   // opens and migrates
        } catch {
            Alerts.error("Super Notes couldn't open its notes database. Notes written now are kept in a temporary file.", error)
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("SuperNotes-\(UUID().uuidString).sqlite")
            store = try! SQLiteNoteStore(url: temp)
        }
        let sync = ICloudDriveSync(store: store)
        Services.store = store
        Services.sync = sync

        runMaintenance(store)
        maintenance = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { runMaintenance(store) }
        }
        sync.start()
    }

    /// Purges expired Void notes, sends long-unmodified notes to The Void (when set) and makes the automatic
    /// backup once its interval has passed.
    @MainActor static func runMaintenance(_ store: SQLiteNoteStore) {
        store.purgeExpiredVoid()
        let days = Defaults[.autoDeleteUnmodifiedDays]
        if days > 0 {
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            for note in store.deck where note.isUnmodified(since: cutoff) { store.moveToVoid(note.id) }
        }
        let interval = Double(max(Defaults[.backupIntervalHours], 1)) * 3600
        guard Date().timeIntervalSince(Defaults[.storageLastAutoBackup]) >= interval else { return }
        do {
            _ = try store.backup()
            Defaults[.storageLastAutoBackup] = Date()
        } catch {
            Log.store.error("automatic backup failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
