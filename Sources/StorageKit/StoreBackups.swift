import Foundation
import SuperNotesCore

// Backups, restore, and JSON export/import.
extension SQLiteNoteStore {
    /// `notes-<timestamp>[-tag].sqlite`, made unique if a file with that name already exists.
    nonisolated static func uniqueBackupURL(in folder: URL, tag: String? = nil) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let base = "notes-" + f.string(from: Date()) + (tag.map { "-" + $0 } ?? "")
        var url = folder.appendingPathComponent(base + ".sqlite")
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base)-\(n).sqlite"); n += 1
        }
        return url
    }

    /// Writes a consistent copy of the open database (`VACUUM INTO`) and prunes old backups.
    public func backup() throws -> URL {
        let dest = Self.uniqueBackupURL(in: SuperNotesPaths.ensure(backupsFolder))
        try db.run("VACUUM INTO ?", [.text(dest.path)])
        pruneBackups(keep: max(Defaults[.backupCount], 1))
        return dest
    }

    /// Backups, newest first.
    public var backups: [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: backupsFolder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("notes-") && $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func pruneBackups(keep: Int) {
        for old in backups.dropFirst(keep) { try? FileManager.default.removeItem(at: old) }
    }

    /// Replaces the database with `backup`. The current notes are saved as a new backup first; sync is turned off
    /// and the restored notes win when it is turned back on.
    public func restore(from backup: URL) throws {
        try Self.validate(backup)
        _ = try self.backup()
        let fm = FileManager.default
        let staged = url.deletingLastPathComponent().appendingPathComponent(".restore-\(UUID().uuidString).sqlite")
        try fm.copyItem(at: backup, to: staged)
        defer { try? fm.removeItem(at: staged) }

        try? db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        db.close()
        do {
            for suffix in ["-wal", "-shm"] { try? fm.removeItem(atPath: url.path + suffix) }
            _ = try fm.replaceItemAt(url, withItemAt: staged)
            db = try Self.open(url, backupsFolder: backupsFolder)
            try load()
        } catch {
            // Reopen whatever is in place (the untouched original when the swap failed).
            db = try Self.open(url, backupsFolder: backupsFolder)
            try load()
            throw error
        }
        try? db.execute("DELETE FROM sync_state")
        Defaults[.syncNotes] = false
        Defaults[.storageSyncLocalWins] = true
        subject.send(.reloaded)
    }

    private nonisolated static func validate(_ file: URL) throws {
        let probe = try SQLiteDatabase(url: file, readOnly: true)
        defer { probe.close() }
        let check = try probe.query("PRAGMA quick_check") { $0.text(0) }.first
        let hasNotes = try probe.scalarInt("SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'notes'") == 1
        guard check == "ok", hasNotes, probe.userVersion <= schemaVersion else {
            throw StorageError(message: "\(file.lastPathComponent) is not a valid Super Notes backup.")
        }
    }

    // MARK: - JSON export / import

    private struct Archive: Codable {
        var format = "supernotes.notes"
        var version = 1
        var exported: Date
        var notes: [Note]
    }

    private static func coder() -> (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder(), d = JSONDecoder()
        e.dateEncodingStrategy = .iso8601
        d.dateDecodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (e, d)
    }

    /// All notes (deck, archive and The Void) as portable JSON.
    public func exportJSON() -> Data {
        let all = deck + archived + void
        return (try? Self.coder().0.encode(Archive(exported: now(), notes: all))) ?? Data()
    }

    /// Merges exported notes by id: unknown notes are added (after the deck), known ones are replaced when the
    /// imported copy was modified later. Returns the number of notes added or updated.
    @discardableResult public func importJSON(_ data: Data) throws -> Int {
        let archive = try Self.coder().1.decode(Archive.self, from: data)
        // "jotter.notes": exports made before the rename to Super Notes (1.2.0).
        guard ["supernotes.notes", "jotter.notes"].contains(archive.format) else {
            throw StorageError(message: "Not a Super Notes export.")
        }
        let t = now()
        var touched: [UUID] = []
        var appended: [UUID] = []
        for var n in archive.notes.sorted(by: { $0.position < $1.position }) {
            if let existing = records[n.id]?.note {
                guard n.modified > existing.modified else { continue }
                n.position = existing.position
                n.slot = existing.slot
            } else {
                if let s = n.slot, records.values.contains(where: { $0.note.slot == s }) { n.slot = nil }
                n.position = Int.max
                if n.deletedAt == nil && !n.isArchived { appended.append(n.id) }
            }
            if n.deletedAt != nil || n.isArchived { n.slot = nil }
            records[n.id] = NoteRecord(note: n, changed: t)
            touched.append(n.id)
        }
        guard !touched.isEmpty else { return 0 }
        let order = deck.map(\.id).filter { !appended.contains($0) } + appended
        persist(touched + renumber(deckOrder: order))
        subject.send(.reloaded)
        return touched.count
    }
}
