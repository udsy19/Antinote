import Foundation
import CryptoKit
import JotterCore

/// The encrypted sync folder: `notes/<id>.jnote` per note (or tombstone), `key.check`, `preferences.jprefs`.
/// Plain file I/O so it works on any folder; `ICloudDriveSync` points it at iCloud Drive.
@MainActor
public final class SyncFolder {
    let root: URL
    private let key: SymmetricKey
    private var notesDir: URL { root.appendingPathComponent("notes", isDirectory: true) }
    var preferencesFile: URL { root.appendingPathComponent("preferences.jprefs") }
    static let tombstoneLifetime: TimeInterval = 180 * 86_400

    /// Decrypted entries by file name, reused while the file's modification date and size are unchanged.
    private var cache: [String: (stamp: String, entry: RemoteEntry)] = [:]

    private struct NoteFile: Codable {
        var id: UUID
        var changed: Date
        /// nil = tombstone (deleted at `changed`).
        var note: Note?
    }

    public init(root: URL, key: SymmetricKey) {
        self.root = root
        self.key = key
    }

    // MARK: Key check

    enum KeyCheck { case missing, matches, mismatch, downloading }

    private var keyCheckFile: URL { root.appendingPathComponent("key.check") }
    nonisolated private static let checkText = Data("jotter-sync-key-check".utf8)

    nonisolated static func keyCheckState(root: URL, key: SymmetricKey?) -> KeyCheck {
        let file = root.appendingPathComponent("key.check")
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: file) else {
            let placeholder = root.appendingPathComponent(".key.check.icloud")
            if fm.fileExists(atPath: placeholder.path) {
                try? fm.startDownloadingUbiquitousItem(at: file)
                return .downloading
            }
            return .missing
        }
        guard let key else { return .mismatch }
        return (try? SyncCrypto.open(data, key: key)) == checkText ? .matches : .mismatch
    }

    func writeKeyCheck() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try SyncCrypto.seal(Self.checkText, key: key).write(to: keyCheckFile, options: .atomic)
    }

    // MARK: Notes

    /// Every readable entry, plus the ids whose files are still downloading (left out of merging).
    func readAll() -> (entries: [UUID: RemoteEntry], pending: Set<UUID>) {
        let fm = FileManager.default
        try? fm.createDirectory(at: notesDir, withIntermediateDirectories: true)
        let names = (try? fm.contentsOfDirectory(atPath: notesDir.path)) ?? []
        var entries: [UUID: RemoteEntry] = [:]
        var pending = Set<UUID>()
        var seen = Set<String>()
        let decoder = JSONDecoder()
        for name in names {
            if name.hasPrefix("."), name.hasSuffix(".jnote.icloud") {
                let real = String(name.dropFirst().dropLast(".icloud".count))
                if let id = UUID(uuidString: String(real.dropLast(".jnote".count))) {
                    pending.insert(id)
                    try? fm.startDownloadingUbiquitousItem(at: notesDir.appendingPathComponent(real))
                }
                continue
            }
            guard name.hasSuffix(".jnote"), let id = UUID(uuidString: String(name.dropLast(".jnote".count))) else { continue }
            seen.insert(name)
            let url = notesDir.appendingPathComponent(name)
            let attrs = (try? fm.attributesOfItem(atPath: url.path)) ?? [:]
            let stamp = "\((attrs[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0)/\((attrs[.size] as? NSNumber)?.intValue ?? -1)"
            if let hit = cache[name], hit.stamp == stamp { entries[id] = hit.entry; continue }
            guard let data = try? Data(contentsOf: url), let plain = try? SyncCrypto.open(data, key: key),
                  let file = try? decoder.decode(NoteFile.self, from: plain), file.id == id else {
                Log.sync.error("unreadable sync file \(name, privacy: .public)")
                pending.insert(id)  // never overwrite what we can't read
                continue
            }
            let entry: RemoteEntry = file.note.map { .note(NoteRecord(note: $0, changed: file.changed)) } ?? .tombstone(file.changed)
            cache[name] = (stamp, entry)
            entries[id] = entry
        }
        cache = cache.filter { seen.contains($0.key) }
        return (entries, pending)
    }

    func write(_ record: NoteRecord) throws {
        try write(NoteFile(id: record.note.id, changed: record.changed, note: record.note))
    }

    func writeTombstone(_ id: UUID, at date: Date) throws {
        try write(NoteFile(id: id, changed: date, note: nil))
    }

    private func write(_ file: NoteFile) throws {
        try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        let sealed = try SyncCrypto.seal(JSONEncoder().encode(file), key: key)
        try sealed.write(to: notesDir.appendingPathComponent(file.id.uuidString + ".jnote"), options: .atomic)
    }

    /// Removes tombstones older than `tombstoneLifetime` (every Mac has long since applied them).
    func pruneTombstones(now: Date) {
        for (name, hit) in cache {
            if case .tombstone(let at) = hit.entry, now.timeIntervalSince(at) > Self.tombstoneLifetime {
                try? FileManager.default.removeItem(at: notesDir.appendingPathComponent(name))
            }
        }
    }

    // MARK: Preferences

    func readPreferences() -> (changed: Date, values: [String: Any])? {
        guard let data = try? Data(contentsOf: preferencesFile), let plain = try? SyncCrypto.open(data, key: key),
              let dict = try? PropertyListSerialization.propertyList(from: plain, format: nil) as? [String: Any],
              let changed = dict["changed"] as? Date, let values = dict["values"] as? [String: Any] else { return nil }
        return (changed, values)
    }

    func writePreferences(changed: Date, values: [String: Any]) throws {
        let plain = try PropertyListSerialization.data(fromPropertyList: ["changed": changed, "values": values],
                                                       format: .binary, options: 0)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try SyncCrypto.seal(plain, key: key).write(to: preferencesFile, options: .atomic)
    }

    // MARK: Sync pass

    /// One full merge of `store` with this folder. Returns the applied plan.
    @discardableResult
    public func sync(_ store: SQLiteNoteStore, localWins: Bool = false) throws -> SyncPlan {
        let (entries, pending) = readAll()
        let now = store.now()
        let local = store.syncSnapshot().filter { !pending.contains($0.key) }
        let base = store.syncBase().filter { !pending.contains($0.key) }
        let plan = SyncMerge.plan(local: local, remote: entries.filter { !pending.contains($0.key) }, base: base,
                                  localWins: localWins, now: now)
        for r in plan.push { try write(r) }
        for id in plan.tombstones { try writeTombstone(id, at: now) }
        // Pending ids keep their previous base so they merge correctly once downloaded.
        store.applySync(plan, keepingBaseOf: pending)
        pruneTombstones(now: now)
        return plan
    }
}
