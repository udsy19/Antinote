import AppKit
import Combine
import SuperNotesCore

extension Defaults.Keys {
    static let storageLastAutoBackup = Key<Date>("storageKit.lastAutoBackup", default: .distantPast)
}

/// Registers this module's services in `Services` (called once at launch).
public enum StorageKitModule {
    @MainActor private static var maintenance: Timer?
    @MainActor private static var retry: Timer?
    @MainActor private static var cancellables: Set<AnyCancellable> = []
    @MainActor private static var announcement: NSObjectProtocol?
    /// Failed writes retry this often until they land.
    static let retryInterval: TimeInterval = 15

    /// Where notes go while the real database can't be opened: next to it, or in the temporary folder when even
    /// that fails. Both are merged back the next time the real database opens.
    nonisolated static var fallbackURLs: [URL] {
        [SuperNotesPaths.support.appendingPathComponent("notes-fallback.sqlite"),
         FileManager.default.temporaryDirectory.appendingPathComponent("SuperNotes-fallback.sqlite")]
    }

    @MainActor public static func install() {
        LegacyMigration.run()   // before the store opens: brings over notes, settings and keys from before the rename
        let store = openStore()
        let sync = ICloudDriveSync(store: store)
        Services.store = store
        Services.sync = sync

        if let recovery = store.recovery { Alerts.error(recovery.message) }
        let recovered = recoverDrafts(into: store)
        if recovered > 0 { announce("Recovered unsaved text") }

        store.saveFailures
            .sink { message in MainActor.assumeIsolated { saveFailed(message) } }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                // Typing first (whatever order the observers fire in), then anything the disk still refuses goes
                // into a JSON file next to the database so it can't vanish with the process.
                Services.windows?.flushEdits()
                if store.hasUnsavedWrites, !store.retryUnsaved() { writeEmergencyExport(store) }
                store.checkpoint()
                NoteDrafts.settle()
            }
        }

        runMaintenance(store)
        maintenance = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { runMaintenance(store) }
        }
        sync.start()
    }

    /// Opens the notes database. A damaged file is recovered inside `SQLiteNoteStore` (backup restored or a fresh
    /// start, the damaged file kept). Any other failure — a newer schema after a downgrade, a read-only or missing
    /// folder — opens a fallback database instead and says so; its notes are merged back once the real one opens.
    @MainActor static func openStore() -> SQLiteNoteStore {
        do {
            let store = try SQLiteNoteStore()
            for url in fallbackURLs {
                if let count = store.absorb(fallback: url), count > 0 { announce("Merged \(count) note\(count == 1 ? "" : "s") written while the database was unavailable") }
            }
            return store
        } catch {
            let kind = (error as? StorageError)?.kind ?? .other
            let reason = kind == .newerVersion
                ? "Your notes were saved by a newer version of Super Notes. Update Super Notes to see them again."
                : "Super Notes couldn't open its notes database."
            Alerts.error(reason + " Notes written now are kept in a separate file and merged back once the database opens again.", error)
            for url in fallbackURLs {
                if let store = try? SQLiteNoteStore(url: url, backupsFolder: url.deletingLastPathComponent().appendingPathComponent("Backups")) {
                    return store
                }
            }
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("SuperNotes-\(UUID().uuidString).sqlite")
            return try! SQLiteNoteStore(url: temp)
        }
    }

    /// Puts the text of every draft file back: an existing note whose text is older than the draft takes it; a
    /// note that changed after the draft (sync) or no longer exists gets the draft as a new note. Blank drafts
    /// are dropped. Returns how many notes were recovered; the draft files are removed.
    @MainActor @discardableResult public static func recoverDrafts(into store: NoteStoring, drafts: [NoteDrafts.Draft] = NoteDrafts.all()) -> Int {
        var count = 0
        for draft in drafts {
            defer { NoteDrafts.remove(draft.id) }
            guard !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if var note = store.note(draft.id) {
                guard note.content != draft.content else { continue }
                if draft.written >= note.modified {
                    note.content = draft.content
                    note.links = draft.links
                    store.update(note)
                } else {
                    store.create(content: draft.content)
                }
            } else {
                store.create(content: draft.content)
            }
            count += 1
        }
        if count > 0 { Log.store.info("recovered \(count) unsaved draft(s)") }
        return count
    }

    /// Says `text` once a titled window is key (there is none this early in launch).
    @MainActor private static func announce(_ text: String) {
        let previous = announcement
        announcement = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                guard (note.object as? NSWindow)?.styleMask.contains(.titled) == true, let token = announcement else { return }
                NotificationCenter.default.removeObserver(token)
                announcement = nil
                DispatchQueue.main.async { HUD.show(text, kind: .success) }
            }
        }
        if let previous { NotificationCenter.default.removeObserver(previous) }
    }

    @MainActor private static func saveFailed(_ message: String) {
        guard retry == nil else { return }   // one message per run of failures
        HUD.show(message, kind: .error)
        retry = Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let store = Services.store as? SQLiteNoteStore, store.retryUnsaved() else { return }
                retry?.invalidate()
                retry = nil
                HUD.show("Notes saved", kind: .success)
            }
        }
    }

    /// `unsaved-notes-<time>.json` next to the database: every note, importable from Settings.
    @MainActor public static func writeEmergencyExport(_ store: SQLiteNoteStore) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let url = store.url.deletingLastPathComponent().appendingPathComponent("unsaved-notes-\(f.string(from: Date())).json")
        do {
            try store.exportJSON().write(to: url, options: .atomic)
            Log.store.error("unsaved notes written to \(url.path, privacy: .public)")
        } catch {
            Log.store.error("emergency export failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Purges expired Void notes, sends long-unmodified notes to The Void (when set), folds the WAL and makes the
    /// automatic backup once its interval has passed.
    @MainActor static func runMaintenance(_ store: SQLiteNoteStore) {
        store.purgeExpiredVoid()
        let days = Defaults[.autoDeleteUnmodifiedDays]
        if days > 0 {
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            for note in store.deck where note.isUnmodified(since: cutoff) { store.moveToVoid(note.id) }
        }
        store.checkpoint()
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
