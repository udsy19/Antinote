import Foundation
import CryptoKit
import SQLite3
import JotterCore
import StorageKit

/// Append cases with `SelfTest.cases.append(("name", { check(..., "msg") }))`.
func registerStorageKitTests() {
    func storageCase(_ name: String, _ body: @escaping @MainActor (URL) throws -> Void) {
        SelfTest.cases.append(("StorageKit.\(name)", {
            MainActor.assumeIsolated {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jotter-storage-\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let suite = "jotter.selftest.storage.\(UUID().uuidString)"
                let savedDefaults = Defaults.store
                Defaults.store = UserDefaults(suiteName: suite)!
                defer {
                    Defaults.store = savedDefaults
                    UserDefaults().removePersistentDomain(forName: suite)
                    try? FileManager.default.removeItem(at: dir)
                }
                do { try body(dir) } catch { check(false, "threw \(error)") }
            }
        }))
    }
    @MainActor func makeStore(_ dir: URL, _ name: String = "notes") throws -> SQLiteNoteStore {
        try SQLiteNoteStore(url: dir.appendingPathComponent("\(name).sqlite"),
                            backupsFolder: dir.appendingPathComponent("\(name)-backups"))
    }
    @MainActor func texts(_ notes: [Note]) -> [String] { notes.map(\.content) }

    storageCase("ordering") { dir in
        let s = try makeStore(dir)
        var events = 0
        let sub = s.changes.sink { _ in events += 1 }
        let a = s.create(content: "a"), b = s.create(content: "b"), c = s.create(content: "c")
        check(texts(s.deck) == ["c", "b", "a"], "new notes go to the front")
        check(s.deck.map(\.position) == [0, 1, 2], "positions are contiguous from 0")
        s.promoteToFront(a.id)
        check(texts(s.deck) == ["a", "c", "b"], "promote to front")
        s.move(a.id, toPosition: 2)
        check(texts(s.deck) == ["c", "b", "a"], "move to position")
        s.move(c.id, toPosition: 99)
        check(texts(s.deck) == ["b", "a", "c"], "move clamps to the end")
        var edited = s.note(b.id)!
        edited.content = "b2"
        s.update(edited)
        check(s.note(b.id)!.modified >= b.modified && s.note(b.id)!.content == "b2", "update saves content")
        check(events == 7, "changes publisher fires (\(events))")
        sub.cancel()
        let reopened = try makeStore(dir)
        check(texts(reopened.deck) == ["b2", "a", "c"], "order survives reopening")
    }

    storageCase("slots") { dir in
        let s = try makeStore(dir)
        let a = s.create(content: "a"), b = s.create(content: "b")
        s.setSlot(0, for: a.id)
        s.setSlot(0, for: b.id)
        check(s.note(a.id)?.slot == nil && s.note(b.id)?.slot == 0, "taking a used slot moves the other note out")
        s.setSlot(1, for: a.id)
        s.moveToVoid(a.id)
        check(s.note(a.id)?.slot == nil, "voided notes leave their slot")
        let reopened = try makeStore(dir)
        check(reopened.note(b.id)?.slot == 0, "slot persists")
    }

    storageCase("void") { dir in
        let s = try makeStore(dir)
        var clock = Date(timeIntervalSinceReferenceDate: 800_000_000)
        s.now = { clock }
        let a = s.create(content: "a"), b = s.create(content: "b"), c = s.create(content: "c")
        s.moveToVoid(b.id)
        check(texts(s.deck) == ["c", "a"] && s.deck.map(\.position) == [0, 1], "void removes from the deck")
        check(s.void.map(\.id) == [b.id] && s.note(b.id)?.deletedAt == clock, "void lists the note with its date")
        s.restoreFromVoid(b.id)
        check(texts(s.deck) == ["b", "c", "a"] && s.void.isEmpty, "restore puts it at the front")
        s.moveToVoid(a.id)
        clock += 10 * 86_400
        s.moveToVoid(c.id)
        clock += 25 * 86_400
        s.purgeExpiredVoid(retentionDays: 0)
        check(s.void.count == 2, "retention 0 keeps forever")
        s.purgeExpiredVoid(retentionDays: 30)
        check(s.void.map(\.id) == [c.id], "only notes older than the retention are purged")
        s.deletePermanently(c.id)
        check(s.void.isEmpty && s.note(c.id) == nil, "delete permanently")
        let empty = s.create(content: "  \n ")
        check(s.deleteIfEmpty(empty.id) && s.note(empty.id) == nil, "empty note deleted")
        check(!s.deleteIfEmpty(b.id), "non-empty note kept")
    }

    storageCase("archiveAndSearch") { dir in
        let s = try makeStore(dir)
        s.create(content: "Groceries\nmilk")
        let cafe = s.create(content: "Café list")
        s.create(content: "math\n2+2")
        s.setArchived(true, for: cafe.id)
        check(s.archived.map(\.id) == [cafe.id] && !s.deck.contains { $0.id == cafe.id }, "archive leaves the deck")
        let positions = (s.deck + s.archived).map(\.position)
        check(Set(positions).count == positions.count, "positions unique among non-deleted notes")
        check(texts(s.search("MILK", includeArchived: false)) == ["Groceries\nmilk"], "case-insensitive search")
        check(s.search("cafe", includeArchived: false).isEmpty, "archived excluded by default")
        check(s.search("CAFE", includeArchived: true).map(\.id) == [cafe.id], "diacritic-insensitive, archived included")
        check(s.search("", includeArchived: false).count == 2, "empty query lists the deck in order")
        s.setArchived(false, for: cafe.id)
        check(s.deck.first?.id == cafe.id, "unarchived note returns to the front")
    }

    storageCase("migrations") { dir in
        let fresh = try makeStore(dir, "fresh")
        check(fresh.deck.isEmpty, "empty database opens")
        // A version-1 file (before sync_state existed) is backed up and upgraded.
        let url = dir.appendingPathComponent("old.sqlite")
        var db: OpaquePointer?
        sqlite3_open(url.path, &db)
        let id = UUID()
        sqlite3_exec(db, """
            create table notes (id text primary key not null, content text not null default '', created real not null,
              modified real not null, changed real not null, position integer not null default 0, slot integer,
              is_locked integer not null default 0, is_read_only integer not null default 0,
              is_archived integer not null default 0, deleted_at real, links text not null default '[]');
            INSERT INTO notes (id, content, created, modified, changed, links)
              VALUES ('\(id.uuidString)', 'old note', 1, 2, 2, '[{"url":"https://example.com/a/b","short":"example.com"}]');
            PRAGMA user_version = 1;
            """, nil, nil, nil)
        sqlite3_close(db)
        let s = try makeStore(dir, "old")
        check(s.note(id)?.content == "old note" && s.note(id)?.links.first?.short == "example.com", "v1 notes load")
        check(s.backups.contains { $0.lastPathComponent.contains("pre-migration-v1") }, "pre-migration backup made")
        sqlite3_open(url.path, &db)
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil)
        sqlite3_step(stmt)
        let version = sqlite3_column_int(stmt, 0)
        sqlite3_finalize(stmt)
        sqlite3_close(db)
        check(version == 2, "migrated to the latest schema (\(version))")
    }

    storageCase("backupRestore") { dir in
        let s = try makeStore(dir)
        let a = s.create(content: "keep me")
        s.setSlot(2, for: a.id)
        let backup = try s.backup()
        check(FileManager.default.fileExists(atPath: backup.path), "backup file written")
        s.deletePermanently(a.id)
        s.create(content: "after backup")
        var reloaded = false
        let sub = s.changes.sink { if case .reloaded = $0 { reloaded = true } }
        try s.restore(from: backup)
        sub.cancel()
        check(texts(s.deck) == ["keep me"] && s.note(a.id)?.slot == 2, "restore brings the backup back")
        check(reloaded, "restore posts .reloaded")
        check(s.backups.count == 2, "current notes saved as a backup before restoring")
        check(!Defaults[.syncNotes], "sync turned off after restoring")
        let reopened = try makeStore(dir)
        check(texts(reopened.deck) == ["keep me"], "restored database persists")
        Defaults[.backupCount] = 2
        for _ in 0..<3 { _ = try s.backup() }
        check(s.backups.count == 2, "old backups pruned to the configured count")

        // JSON export/import round trip, merging by id.
        let json = s.exportJSON()
        let other = try makeStore(dir, "other")
        other.create(content: "local only")
        let imported = try other.importJSON(json)
        check(imported == 1, "one note imported")
        check(texts(other.deck) == ["local only", "keep me"], "imported notes appended after the deck")
        let reimported = try other.importJSON(json)
        check(reimported == 0, "re-import changes nothing")
    }

    SelfTest.cases.append(("StorageKit.encryption", {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("secret note ✓".utf8)
        let sealed = try? SyncCrypto.seal(plain, key: key)
        check(sealed != nil && sealed != plain, "seals")
        check(sealed.flatMap { try? SyncCrypto.open($0, key: key) } == plain, "round trip")
        check(sealed.flatMap { try? SyncCrypto.open($0, key: SymmetricKey(size: .bits256)) } == nil, "wrong key rejected")
        if var tampered = sealed {
            tampered[tampered.count - 1] ^= 1
            check((try? SyncCrypto.open(tampered, key: key)) == nil, "tampering detected")
        }
    }))

    SelfTest.cases.append(("StorageKit.mergeRules", {
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000), t1 = t0 + 10, t2 = t0 + 20
        func rec(_ id: UUID, _ text: String, _ changed: Date) -> NoteRecord {
            NoteRecord(note: Note(id: id, content: text, created: t0, modified: changed), changed: changed)
        }
        let id = UUID()
        var p = SyncMerge.plan(local: [id: rec(id, "new", t1)], remote: [id: .note(rec(id, "old", t0))], base: [id: t0], now: t2)
        check(p.push.map(\.note.content) == ["new"] && p.apply.isEmpty, "local-only change is pushed")
        p = SyncMerge.plan(local: [id: rec(id, "old", t0)], remote: [id: .note(rec(id, "new", t1))], base: [id: t0], now: t2)
        check(p.apply.map(\.note.content) == ["new"] && p.push.isEmpty, "remote-only change is applied")
        p = SyncMerge.plan(local: [id: rec(id, "mine", t1)], remote: [id: .note(rec(id, "theirs", t2))], base: [id: t0], now: t2)
        check(p.conflicts == 1 && p.apply.contains { $0.note.id == id && $0.note.content == "theirs" }, "newer side wins")
        check(p.apply.contains { $0.note.id != id && $0.note.content.hasPrefix("Sync conflict") && $0.note.content.hasSuffix("\nmine") },
              "older side kept as a conflict copy")
        p = SyncMerge.plan(local: [id: rec(id, "old", t0)], remote: [id: .tombstone(t1)], base: [id: t0], now: t2)
        check(p.delete == [id], "tombstone deletes an untouched note")
        p = SyncMerge.plan(local: [id: rec(id, "edited", t1)], remote: [id: .tombstone(t1)], base: [id: t0], now: t2)
        check(p.delete.isEmpty && p.push.count == 1, "edit after deletion survives")
        p = SyncMerge.plan(local: [:], remote: [id: .note(rec(id, "old", t0))], base: [id: t0], now: t2)
        check(p.tombstones == [id], "local deletion becomes a tombstone")
        p = SyncMerge.plan(local: [:], remote: [id: .note(rec(id, "x", t0))], base: [:], localWins: true, now: t2)
        check(p.tombstones == [id] && p.apply.isEmpty, "after a restore local notes win")
        p = SyncMerge.plan(local: [id: rec(id, "same", t1)], remote: [id: .note(rec(id, "same", t1))], base: [:], now: t2)
        check(p.isEmpty && p.base[id] == t1, "identical sides only record the base")
    }))

    storageCase("folderSync") { dir in
        let cloud = dir.appendingPathComponent("cloud")
        let key = SymmetricKey(size: .bits256)
        let macA = try makeStore(dir, "macA"), macB = try makeStore(dir, "macB")
        let folderA = SyncFolder(root: cloud, key: key), folderB = SyncFolder(root: cloud, key: key)
        let shared = macA.create(content: "shared")
        let gone = macA.create(content: "to delete")
        try folderA.sync(macA)
        try folderB.sync(macB)
        check(Set(texts(macB.deck)) == ["shared", "to delete"], "notes arrive on the other Mac")
        let raw = (try? FileManager.default.contentsOfDirectory(at: cloud.appendingPathComponent("notes"), includingPropertiesForKeys: nil)) ?? []
        check(raw.count == 2 && raw.allSatisfy { !(String(data: (try? Data(contentsOf: $0)) ?? Data(), encoding: .utf8) ?? "").contains("shared") },
              "files are encrypted")

        // Both Macs edit the same note before syncing → both versions kept.
        var onA = macA.note(shared.id)!; onA.content = "edited on A"; macA.update(onA)
        macB.now = { Date() + 5 }
        var onB = macB.note(shared.id)!; onB.content = "edited on B"; macB.update(onB)
        macA.deletePermanently(gone.id)
        try folderA.sync(macA)
        try folderB.sync(macB)
        try folderA.sync(macA)
        check(macA.note(shared.id)?.content == "edited on B" && macB.note(shared.id)?.content == "edited on B", "newest edit wins")
        let copies = macA.deck.filter { $0.content.hasPrefix("Sync conflict") }
        check(copies.count == 1 && copies.first?.content.hasSuffix("edited on A") == true, "conflict copy kept")
        check(macB.deck.contains { $0.id == copies.first?.id }, "conflict copy synced to the other Mac")
        check(macB.note(gone.id) == nil, "permanent deletion propagates")
        let settledB = try folderB.sync(macB), settledA = try folderA.sync(macA)
        check(settledB.isEmpty && settledA.isEmpty, "converged")

        // Void state syncs too.
        macB.moveToVoid(shared.id)
        try folderB.sync(macB)
        try folderA.sync(macA)
        check(macA.note(shared.id)?.isInVoid == true, "moving to The Void syncs")
    }
}
