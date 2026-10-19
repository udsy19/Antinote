import Foundation
import Combine
import SuperNotesCore

/// A note plus its sync revision time (`changed` moves on any synced-field change; `note.modified` only on edits).
public struct NoteRecord: Codable, Equatable, Sendable {
    public var note: Note
    public var changed: Date
    public init(note: Note, changed: Date) { self.note = note; self.changed = changed }
}

extension Defaults.Keys {
    /// Set by a backup restore: the next sync pushes local notes over the folder ("these notes win").
    static let storageSyncLocalWins = Key<Bool>("storageKit.syncLocalWins", default: false)
}

/// What `init` did when the database file turned out to be damaged: the damaged file is never deleted, it is
/// moved into the backups folder.
public enum StoreRecovery: Equatable, Sendable {
    case restoredBackup(URL, damaged: URL)
    case startedFresh(damaged: URL)

    /// Plain words for the user.
    public var message: String {
        switch self {
        case let .restoredBackup(backup, damaged):
            "Your notes database was damaged, so the backup “\(backup.deletingPathExtension().lastPathComponent)” was "
                + "restored. Notes written after that backup may be missing. The damaged file is kept as "
                + "“\(damaged.lastPathComponent)” in the Backups folder."
        case let .startedFresh(damaged):
            "Your notes database was damaged and no backup could be read, so Super Notes starts with an empty one. "
                + "The damaged file is kept as “\(damaged.lastPathComponent)” in the Backups folder."
        }
    }
}

/// SQLite-backed `NoteStoring`. All notes are cached in memory and written through to the database.
@MainActor
public final class SQLiteNoteStore: NoteStoring {
    public let url: URL
    let backupsFolder: URL
    /// Clock; replaced by tests.
    public var now: () -> Date = Date.init
    /// Set when opening found the file damaged and recovered (see `StoreRecovery`); the module tells the user.
    public private(set) var recovery: StoreRecovery?

    var db: SQLiteDatabase
    var records: [UUID: NoteRecord] = [:]
    let subject = PassthroughSubject<NoteStoreChange, Never>()
    /// Notes (and deletions) whose last write failed — a full disk, a read-only file. The in-memory copy is the
    /// truth; every later write retries them, and `retryUnsaved()` does so on a timer.
    public private(set) var unsavedNoteIDs: Set<UUID> = []
    private var unsavedRemovals: Set<UUID> = []
    private let saveFailureSubject = PassthroughSubject<String, Never>()
    /// The message of each failed write, in plain words (shown once per run of failures).
    public var saveFailures: AnyPublisher<String, Never> { saveFailureSubject.eraseToAnyPublisher() }

    public init(url: URL = SuperNotesPaths.database, backupsFolder: URL = SuperNotesPaths.backups) throws {
        self.url = url
        self.backupsFolder = SuperNotesPaths.ensure(backupsFolder)
        SuperNotesPaths.ensure(url.deletingLastPathComponent())
        do {
            db = try SQLiteNoteStore.open(url, backupsFolder: backupsFolder)
        } catch let error as StorageError where error.kind == .damaged {
            Log.store.error("notes database damaged: \(error.message, privacy: .public)")
            (db, recovery) = try SQLiteNoteStore.recover(url, backupsFolder: backupsFolder, cause: error)
        }
        try load()
    }

    // MARK: - Schema

    /// Migration `i` upgrades `user_version` i → i+1. Append only; never edit a shipped migration.
    /// Dates are floating-point seconds since 2001-01-01 (Foundation's reference date, so they round-trip exactly).
    nonisolated static let migrations: [String] = [
        """
        create table notes (
            id text primary key not null,
            content text not null default '',
            created real not null,
            modified real not null,
            changed real not null,
            position integer not null default 0,
            slot integer,
            is_locked integer not null default 0,
            is_read_only integer not null default 0,
            is_archived integer not null default 0,
            deleted_at real,
            links text not null default '[]'
        );
        create unique index notes_slot on notes(slot) where slot is not null;
        create index notes_position on notes(position) where deleted_at is null;
        create index notes_deleted_at on notes(deleted_at) where deleted_at is not null;
        """,
        """
        create table sync_state (
            id text primary key not null,
            synced_changed real not null
        );
        """,
    ]
    nonisolated static var schemaVersion: Int { migrations.count }

    /// Opens, configures, checks and migrates a database file. Older files are backed up before migrating.
    /// WAL with `synchronous = FULL`: every commit is on disk before the write returns, so a crash, a forced quit or
    /// a power cut loses nothing that was saved (NORMAL would let a power cut roll back the last commits).
    static func open(_ url: URL, backupsFolder: URL) throws -> SQLiteDatabase {
        let db = try SQLiteDatabase(url: url)
        try db.execute("PRAGMA journal_mode = WAL; PRAGMA synchronous = FULL; PRAGMA foreign_keys = ON;")
        let check = try db.query("PRAGMA quick_check") { $0.text(0) }.first ?? "no result"
        guard check == "ok" else { throw StorageError(message: "The notes database is damaged: \(check)", kind: .damaged) }
        let version = db.userVersion
        guard version <= schemaVersion else {
            throw StorageError(message: "The notes database was saved by a newer version of Super Notes.", kind: .newerVersion)
        }
        if version > 0 && version < schemaVersion {
            let dest = uniqueBackupURL(in: backupsFolder, tag: "pre-migration-v\(version)")
            do { try db.run("VACUUM INTO ?", [.text(dest.path)]) } catch {
                Log.store.error("pre-migration backup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        for (i, sql) in migrations.enumerated() where i >= version {
            try db.transaction {
                try db.execute(sql)
                try db.execute("PRAGMA user_version = \(i + 1)")
            }
        }
        // Schema v1 files were created without the sync table; make sure every table this build reads is there.
        guard try db.scalarInt("SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'notes'") == 1 else {
            throw StorageError(message: "The notes database has no notes table.", kind: .damaged)
        }
        return db
    }

    /// The damaged file (with its `-wal`/`-shm`) moves into the backups folder as `notes-<time>-damaged.sqlite`, then
    /// the newest backup that passes `validate` is copied into place; without one, a fresh database starts. Nothing
    /// is deleted. Throws `cause` when the damaged file can't even be moved aside (the folder is read-only).
    static func recover(_ url: URL, backupsFolder: URL, cause: StorageError) throws -> (SQLiteDatabase, StoreRecovery) {
        let fm = FileManager.default
        let damaged = uniqueBackupURL(in: SuperNotesPaths.ensure(backupsFolder), tag: "damaged")
        for suffix in ["", "-wal", "-shm"] where fm.fileExists(atPath: url.path + suffix) {
            try? fm.moveItem(atPath: url.path + suffix, toPath: damaged.path + suffix)
        }
        guard !fm.fileExists(atPath: url.path) else { throw cause }
        for backup in backups(in: backupsFolder) where backup != damaged && (try? validate(backup)) != nil {
            do {
                try fm.copyItem(at: backup, to: url)
                let db = try open(url, backupsFolder: backupsFolder)
                Log.store.error("restored \(backup.lastPathComponent, privacy: .public) over the damaged database")
                return (db, .restoredBackup(backup, damaged: damaged))
            } catch {
                for suffix in ["", "-wal", "-shm"] { try? fm.removeItem(atPath: url.path + suffix) }
            }
        }
        let db = try open(url, backupsFolder: backupsFolder)
        Log.store.error("no readable backup; started a fresh database")
        return (db, .startedFresh(damaged: damaged))
    }

    /// Folds the WAL into the main file (quit, hourly maintenance); harmless while writes carry on.
    public func checkpoint() {
        try? db.execute("PRAGMA wal_checkpoint(PASSIVE)")
    }

    /// Tests only: caps the file at `pages` pages so the next write that needs room fails the way a full disk does
    /// (`SQLITE_FULL`). 0 lifts the cap.
    public func setPageLimit(_ pages: Int) {
        try? db.execute("PRAGMA max_page_count = \(pages > 0 ? pages : 1_073_741_823)")
    }

    func load() throws {
        let decoder = JSONDecoder()
        let rows = try db.query("""
            SELECT id, content, created, modified, changed, position, slot, is_locked, is_read_only, is_archived,
                   deleted_at, links FROM notes
            """) { r -> NoteRecord? in
            guard let id = UUID(uuidString: r.text(0)) else { return nil }
            let links = (try? decoder.decode([ShortLink].self, from: Data(r.text(11).utf8))) ?? []
            let note = Note(id: id, content: r.text(1), created: Date(timeIntervalSinceReferenceDate: r.double(2)),
                            modified: Date(timeIntervalSinceReferenceDate: r.double(3)), position: r.int(5),
                            slot: r.isNull(6) ? nil : r.int(6), isLocked: r.int(7) != 0, isReadOnly: r.int(8) != 0,
                            isArchived: r.int(9) != 0,
                            deletedAt: r.isNull(10) ? nil : Date(timeIntervalSinceReferenceDate: r.double(10)), links: links)
            return NoteRecord(note: note, changed: Date(timeIntervalSinceReferenceDate: r.double(4)))
        }
        records = Dictionary(rows.compactMap { $0 }.map { ($0.note.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Writing

    /// Upserts the given records (in order — slot hand-overs clear the old owner first) and deletes `removed`, plus
    /// whatever an earlier write left unsaved. The transaction either lands whole or not at all: a failure keeps the
    /// previous version on disk, the new one in memory, and is reported through `saveFailures`.
    func persist(_ ids: [UUID], removed: [UUID] = []) {
        let removed = Set(removed).union(unsavedRemovals).filter { records[$0] == nil }
        let ids = ids + Array(unsavedNoteIDs.subtracting(ids))
        let encoder = JSONEncoder()
        do {
            try db.transaction {
                for id in removed { try db.run("DELETE FROM notes WHERE id = ?", [.text(id.uuidString)]) }
                for id in ids {
                    guard let r = records[id] else { continue }
                    let n = r.note
                    let links = String(data: (try? encoder.encode(n.links)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
                    try db.run("""
                        INSERT INTO notes (id, content, created, modified, changed, position, slot, is_locked,
                                           is_read_only, is_archived, deleted_at, links)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET content = excluded.content, created = excluded.created,
                            modified = excluded.modified, changed = excluded.changed, position = excluded.position,
                            slot = excluded.slot, is_locked = excluded.is_locked, is_read_only = excluded.is_read_only,
                            is_archived = excluded.is_archived, deleted_at = excluded.deleted_at, links = excluded.links
                        """, [.text(n.id.uuidString), .text(n.content), .date(n.created), .date(n.modified),
                              .date(r.changed), .int(Int64(n.position)), .optInt(n.slot), .bool(n.isLocked),
                              .bool(n.isReadOnly), .bool(n.isArchived), .date(n.deletedAt), .text(links)])
                }
            }
            unsavedNoteIDs = []
            unsavedRemovals = []
        } catch {
            unsavedNoteIDs.formUnion(ids.filter { records[$0] != nil })
            unsavedRemovals.formUnion(removed)
            Log.store.error("save failed: \(error.localizedDescription, privacy: .public)")
            saveFailureSubject.send("Your notes can't be saved right now (\(error.localizedDescription)). "
                                    + "They stay in memory; free up space or fix the notes folder and Super Notes will keep trying.")
        }
    }

    /// Whether a write is still owed to the disk.
    public var hasUnsavedWrites: Bool { !unsavedNoteIDs.isEmpty || !unsavedRemovals.isEmpty }

    /// Writes what earlier failures left unsaved; returns whether everything is on disk afterwards.
    @discardableResult public func retryUnsaved() -> Bool {
        if hasUnsavedWrites { persist([]) }
        return !hasUnsavedWrites
    }

    /// Renumbers positions: `deckOrder` gets 0…, archived notes follow (keeping their order), Void notes get -1.
    /// Returns the ids whose position changed.
    func renumber(deckOrder: [UUID]) -> [UUID] {
        var changed: [UUID] = []
        func set(_ id: UUID, _ pos: Int) {
            guard records[id]?.note.position != pos else { return }
            records[id]?.note.position = pos
            changed.append(id)
        }
        for (i, id) in deckOrder.enumerated() { set(id, i) }
        let archived = records.values.filter { $0.note.isArchived && $0.note.deletedAt == nil && !deckOrder.contains($0.note.id) }
            .sorted { ($0.note.position, $0.note.id.uuidString) < ($1.note.position, $1.note.id.uuidString) }
        for (i, r) in archived.enumerated() { set(r.note.id, deckOrder.count + i) }
        for r in records.values where r.note.deletedAt != nil { set(r.note.id, -1) }
        return changed
    }

    private var deckIDs: [UUID] { deck.map(\.id) }

    // MARK: - NoteStoring

    public var deck: [Note] {
        records.values.map(\.note).filter { $0.deletedAt == nil && !$0.isArchived }.sorted { $0.position < $1.position }
    }

    public var void: [Note] {
        records.values.map(\.note).filter { $0.deletedAt != nil }.sorted { $0.deletedAt! > $1.deletedAt! }
    }

    public var archived: [Note] {
        records.values.map(\.note).filter { $0.deletedAt == nil && $0.isArchived }.sorted { $0.position < $1.position }
    }

    public func note(_ id: UUID) -> Note? { records[id]?.note }

    public var changes: AnyPublisher<NoteStoreChange, Never> { subject.eraseToAnyPublisher() }

    @discardableResult public func create(content: String) -> Note {
        let t = now()
        let note = Note(content: content, created: t, modified: t, position: 0)
        let order = [note.id] + deckIDs
        records[note.id] = NoteRecord(note: note, changed: t)
        persist([note.id] + renumber(deckOrder: order))
        subject.send(.inserted(note.id))
        return records[note.id]!.note
    }

    public func update(_ note: Note) {
        guard var r = records[note.id] else { return }
        let contentChanged = r.note.content != note.content
        guard contentChanged || r.note.isLocked != note.isLocked || r.note.isReadOnly != note.isReadOnly
                || r.note.links != note.links else { return }
        let t = now()
        r.note.content = note.content
        r.note.isLocked = note.isLocked
        r.note.isReadOnly = note.isReadOnly
        r.note.links = note.links
        if contentChanged { r.note.modified = t }
        r.changed = t
        records[note.id] = r
        persist([note.id])
        subject.send(.updated(note.id))
    }

    public func moveToVoid(_ id: UUID) {
        guard let r = records[id], r.note.deletedAt == nil else { return }
        let t = now()
        records[id]?.note.deletedAt = t
        records[id]?.note.slot = nil
        records[id]?.changed = t
        persist([id] + renumber(deckOrder: deckIDs))
        subject.send(.removed(id))
    }

    public func restoreFromVoid(_ id: UUID) {
        guard records[id]?.note.deletedAt != nil else { return }
        records[id]?.note.deletedAt = nil
        records[id]?.note.isArchived = false
        records[id]?.changed = now()
        persist([id] + renumber(deckOrder: [id] + deckIDs.filter { $0 != id }))
        subject.send(.inserted(id))
    }

    public func deletePermanently(_ id: UUID) {
        deletePermanently([id])
    }

    func deletePermanently(_ ids: [UUID]) {
        let existing = ids.filter { records[$0] != nil }
        guard !existing.isEmpty else { return }
        for id in existing { records[id] = nil }
        persist(renumber(deckOrder: deckIDs), removed: existing)
        existing.forEach { subject.send(.removed($0)) }
    }

    public func purgeExpiredVoid() {
        purgeExpiredVoid(retentionDays: Defaults[.voidRetentionDays])
    }

    /// Deletes Void notes deleted more than `retentionDays` days ago (0 = keep forever).
    public func purgeExpiredVoid(retentionDays: Int) {
        guard retentionDays > 0 else { return }
        let cutoff = now().addingTimeInterval(-Double(retentionDays) * 86_400)
        deletePermanently(void.filter { $0.deletedAt! < cutoff }.map(\.id))
    }

    public func promoteToFront(_ id: UUID) {
        move(id, toPosition: 0)
    }

    public func move(_ id: UUID, toPosition: Int) {
        var order = deckIDs
        guard let from = order.firstIndex(of: id) else { return }
        order.remove(at: from)
        order.insert(id, at: max(0, min(toPosition, order.count)))
        let changed = renumber(deckOrder: order)
        guard !changed.isEmpty else { return }
        persist(changed)
        subject.send(.reordered)
    }

    public func setSlot(_ slot: Int?, for id: UUID) {
        guard let r = records[id], r.note.deletedAt == nil, r.note.slot != slot else { return }
        var ids: [UUID] = []
        if let slot, let other = records.values.first(where: { $0.note.slot == slot })?.note.id {
            records[other]?.note.slot = nil
            ids.append(other)
        }
        records[id]?.note.slot = slot
        ids.append(id)
        persist(ids)
        ids.forEach { subject.send(.updated($0)) }
    }

    public func setArchived(_ archived: Bool, for id: UUID) {
        guard let r = records[id], r.note.deletedAt == nil, r.note.isArchived != archived else { return }
        records[id]?.note.isArchived = archived
        records[id]?.changed = now()
        let order: [UUID]
        if archived {
            records[id]?.note.slot = nil
            records[id]?.note.position = Int.max   // newest archived goes last
            order = deckIDs
        } else {
            order = [id] + deckIDs.filter { $0 != id }
        }
        persist([id] + renumber(deckOrder: order))
        subject.send(.updated(id))
    }

    public func search(_ query: String, includeArchived: Bool) -> [Note] {
        let pool = includeArchived ? deck + archived : deck
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return pool }
        return pool.filter { $0.content.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Deletes the note permanently when it has no visible text (the shell calls this when leaving a note).
    @discardableResult public func deleteIfEmpty(_ id: UUID) -> Bool {
        guard let n = records[id]?.note, n.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        deletePermanently(id)
        return true
    }
}
