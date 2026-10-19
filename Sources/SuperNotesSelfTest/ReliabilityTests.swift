import AppKit
import Combine
import SQLite3
import SuperNotesCore
import StorageKit
import ShellKit
import ToolsKit

/// Data-loss drills (docs/specs/reliability.md): a full disk, a damaged or downgraded database, a crash between a
/// keystroke and the save, switching notes mid-debounce, links that rewrite notes, odd text. Every case works in a
/// throwaway folder.
func registerReliabilityTests() {
    func storageCase(_ name: String, _ body: @escaping @MainActor (URL) throws -> Void) {
        SelfTest.cases.append(("Reliability.\(name)", {
            MainActor.assumeIsolated {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("supernotes-reliability-\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let suite = "supernotes.selftest.reliability.\(UUID().uuidString)"
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
        try SQLiteNoteStore(url: dir.appendingPathComponent("\(name).sqlite"), backupsFolder: dir.appendingPathComponent("\(name)-backups"))
    }
    @MainActor func texts(_ notes: [Note]) -> [String] { notes.map(\.content) }
    func overwrite(_ url: URL, from offset: Int, with byte: UInt8) throws {
        var data = try Data(contentsOf: url)
        for i in offset..<data.count { data[i] = byte }
        try data.write(to: url)
    }
    let big = String(repeating: "x", count: 300_000)

    // The disk fills up mid-session: the version on disk stays whole, the new text stays in memory and is reported,
    // and it lands as soon as there is room again.
    storageCase("diskFull") { dir in
        let s = try makeStore(dir)
        let a = s.create(content: "v1")
        let b = s.create(content: "to be deleted")
        var problems: [String] = []
        let sub = s.saveFailures.sink { problems.append($0) }
        defer { sub.cancel() }
        s.setPageLimit(1)   // clamps to the current size: nothing may grow
        var edited = a
        edited.content = big
        s.update(edited)
        check(s.note(a.id)?.content == big, "the new text stays in memory")
        check(s.unsavedNoteIDs == [a.id], "the note is marked unsaved: \(s.unsavedNoteIDs)")
        check(problems.count == 1 && problems[0].contains("can't be saved"), "the failure is reported in plain words: \(problems)")
        let onDisk = try makeStore(dir, "notes")
        check(onDisk.note(a.id)?.content == "v1", "the previous version on disk is intact")
        s.deletePermanently(b.id)
        check(s.note(b.id) == nil && s.hasUnsavedWrites, "a deletion the disk refused is owed too")
        s.setPageLimit(0)
        check(s.retryUnsaved() && s.unsavedNoteIDs.isEmpty, "the retry writes everything once there is room")
        let reopened = try makeStore(dir)
        check(reopened.note(a.id)?.content == big && reopened.note(b.id) == nil, "both the edit and the deletion reached the disk")
    }

    // Writes failing after a quit are not thrown away: the module writes a JSON export next to the database.
    storageCase("emergencyExport") { dir in
        let s = try makeStore(dir)
        let a = s.create(content: "saved")
        s.setPageLimit(1)
        var edited = a
        edited.content = big
        s.update(edited)
        StorageKitModule.writeEmergencyExport(s)
        let exports = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("unsaved-notes-") } ?? []
        check(exports.count == 1, "one export written: \(exports.map(\.lastPathComponent))")
        if let url = exports.first, let data = try? Data(contentsOf: url) {
            let other = try makeStore(dir, "other")
            let imported = try other.importJSON(data)
            check(imported == 1 && other.note(a.id)?.content == big, "the export carries the unsaved text and imports")
        }
    }

    // The database file is damaged at launch: it is kept, the newest readable backup comes back, the user is told.
    storageCase("damagedDatabaseRestoresBackup") { dir in
        var s: SQLiteNoteStore? = try makeStore(dir)
        let kept = s!.create(content: "in the backup")
        _ = try s!.backup()
        s!.create(content: "after the backup")
        s = nil   // closes the file
        let url = dir.appendingPathComponent("notes.sqlite")
        for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        try overwrite(url, from: 0, with: 0x41)   // "AAAA…": not a database at all
        let recovered = try makeStore(dir)
        guard case let .restoredBackup(backup, damaged)? = recovered.recovery else {
            return check(false, "recovery reported: \(String(describing: recovered.recovery))")
        }
        check(texts(recovered.deck) == ["in the backup"] && recovered.note(kept.id) != nil, "the backup's notes are back")
        check(damaged.lastPathComponent.contains("-damaged") && FileManager.default.fileExists(atPath: damaged.path),
              "the damaged file is kept in the backups folder: \(damaged.lastPathComponent)")
        check(backup.lastPathComponent.hasPrefix("notes-") && recovered.recovery?.message.contains("was damaged") == true,
              "the message names what happened")
        recovered.create(content: "new after recovery")
        let live = try makeStore(dir)
        check(texts(live.deck) == ["new after recovery", "in the backup"], "the recovered database is the live one")
        // A damaged body behind a good header (SQLITE_CORRUPT / quick_check) is caught the same way.
        var t: SQLiteNoteStore? = try makeStore(dir, "torn")
        for _ in 0..<40 { t!.create(content: String(repeating: "y", count: 2000)) }
        t!.checkpoint()
        t = nil
        let torn = dir.appendingPathComponent("torn.sqlite")
        for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: torn.path + suffix) }
        try overwrite(torn, from: 4096, with: 0x00)
        let fresh = try makeStore(dir, "torn")
        if case .startedFresh? = fresh.recovery {
            check(fresh.deck.isEmpty, "no backup: starts empty")
            check(SQLiteNoteStore.isRotated(torn) == false, "helper sanity")
        } else {
            check(false, "torn body not detected: \(String(describing: fresh.recovery))")
        }
    }

    // A downgrade after an update (the schema is newer than this build): nothing is touched or moved.
    storageCase("newerSchemaLeavesFileAlone") { dir in
        var s: SQLiteNoteStore? = try makeStore(dir)
        s!.create(content: "from the future")
        s!.checkpoint()
        s = nil
        let url = dir.appendingPathComponent("notes.sqlite")
        var db: OpaquePointer?
        sqlite3_open(url.path, &db)
        sqlite3_exec(db, "PRAGMA user_version = 99", nil, nil, nil)
        sqlite3_close(db)
        let before = try Data(contentsOf: url)
        do {
            _ = try makeStore(dir)
            check(false, "a newer schema must not open")
        } catch let error as StorageError {
            check(error.kind == .newerVersion && error.message.contains("newer version"), "refused with the reason: \(error.message)")
        }
        let after = try Data(contentsOf: url)
        check(after == before, "the file is byte-for-byte as it was")
        check(SQLiteNoteStore.backups(in: dir.appendingPathComponent("notes-backups")).isEmpty, "no 'damaged' copy was made")
        // Meanwhile notes go to a fallback file and are merged back once the real database opens.
        let fallback = dir.appendingPathComponent("notes-fallback.sqlite")
        var f: SQLiteNoteStore? = try SQLiteNoteStore(url: fallback, backupsFolder: dir.appendingPathComponent("fb"))
        f!.create(content: "written during the outage")
        f = nil
        sqlite3_open(url.path, &db)
        sqlite3_exec(db, "PRAGMA user_version = 2", nil, nil, nil)
        sqlite3_close(db)
        let back = try makeStore(dir)
        check(back.absorb(fallback: fallback) == 1 && texts(back.deck) == ["from the future", "written during the outage"],
              "fallback notes merged after the deck: \(texts(back.deck))")
        check(!FileManager.default.fileExists(atPath: fallback.path) && back.absorb(fallback: fallback) == nil, "the fallback file is gone")
    }

    // The file can't be written (permissions changed): no data is moved or lost; writes are reported, not dropped.
    storageCase("readOnlyFile") { dir in
        var s: SQLiteNoteStore? = try makeStore(dir)
        let a = s!.create(content: "mine")
        s!.checkpoint()
        s = nil
        let url = dir.appendingPathComponent("notes.sqlite")
        for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        var opened = false
        do {
            let r = try makeStore(dir)
            opened = true
            check(r.note(a.id)?.content == "mine", "notes still readable")
            var edited = a
            edited.content = "changed while read-only"
            r.update(edited)
            check(r.unsavedNoteIDs.contains(a.id) || r.note(a.id)?.content == "changed while read-only",
                  "the edit is kept in memory and owed to the disk")
        } catch let error as StorageError {
            check(error.kind == .other, "a permissions problem is not 'damaged': \(error.message)")
        }
        check(FileManager.default.fileExists(atPath: url.path)
              && SQLiteNoteStore.backups(in: dir.appendingPathComponent("notes-backups")).isEmpty,
              "the file stays where it is, no 'damaged' copy (opened: \(opened))")
    }

    // Rotation only counts routine backups; the pre-migration and damaged copies are safety nets outside it.
    storageCase("backupRotationSparesSafetyCopies") { dir in
        let s = try makeStore(dir)
        s.create(content: "a")
        let folder = dir.appendingPathComponent("notes-backups")
        let pre = SQLiteNoteStore.uniqueBackupURL(in: folder, tag: "pre-migration-v1")
        let damaged = SQLiteNoteStore.uniqueBackupURL(in: folder, tag: "damaged")
        FileManager.default.createFile(atPath: pre.path, contents: Data("old".utf8))
        FileManager.default.createFile(atPath: damaged.path, contents: Data("bad".utf8))
        Defaults[.backupCount] = 1
        for _ in 0..<3 { _ = try s.backup() }
        let names = s.backups.map(\.lastPathComponent)
        check(names.count == 3 && names.contains(pre.lastPathComponent) && names.contains(damaged.lastPathComponent),
              "one routine backup kept, both safety copies untouched: \(names)")
        check(SQLiteNoteStore.isRotated(URL(fileURLWithPath: "/x/notes-20260101-120000-000.sqlite"))
              && SQLiteNoteStore.isRotated(URL(fileURLWithPath: "/x/notes-20260101-120000-000-2.sqlite"))
              && !SQLiteNoteStore.isRotated(pre) && !SQLiteNoteStore.isRotated(damaged), "what counts as a routine backup")
        Defaults[.backupCount] = -5
        _ = try s.backup()
        check(s.backups.filter(SQLiteNoteStore.isRotated).count == 1, "a bad count still keeps the newest backup")
    }

    // Draft files put typing back after a crash: newer than the note → the note takes it; the note changed since
    // (sync) or is gone → a new note; blank drafts are dropped. Files are removed afterwards.
    storageCase("draftRecovery") { dir in
        let s = try makeStore(dir)
        var clock = Date(timeIntervalSinceReferenceDate: 800_000_000)
        s.now = { clock }
        let a = s.create(content: "saved text")
        let synced = s.create(content: "changed on another Mac")
        clock += 10
        let gone = UUID()
        let drafts = [
            NoteDrafts.Draft(id: a.id, content: "saved text plus what I typed", written: clock),
            NoteDrafts.Draft(id: synced.id, content: "older draft", written: clock - 100),
            NoteDrafts.Draft(id: gone, content: "note that no longer exists", written: clock),
            NoteDrafts.Draft(id: UUID(), content: "  \n ", written: clock),
        ]
        let count = StorageKitModule.recoverDrafts(into: s, drafts: drafts)
        check(count == 3, "three notes recovered (\(count))")
        check(s.note(a.id)?.content == "saved text plus what I typed", "the newer draft replaces the note's text")
        check(s.note(synced.id)?.content == "changed on another Mac", "a note changed after the draft keeps its text")
        check(Set(texts(s.deck)).isSuperset(of: ["older draft", "note that no longer exists"]), "the rest arrive as new notes: \(texts(s.deck))")
        check(s.deck.count == 4, "the blank draft made nothing")
        check(StorageKitModule.recoverDrafts(into: s, drafts: [NoteDrafts.Draft(id: a.id, content: "saved text plus what I typed")]) == 0,
              "a draft equal to the note is a no-op")
        // The file side: write, coalesce, list, remove.
        let id = UUID()
        NoteDrafts.write(NoteDrafts.Draft(id: id, content: "first"))
        NoteDrafts.write(NoteDrafts.Draft(id: id, content: "second"))
        check(NoteDrafts.all().first { $0.id == id }?.content == "second", "the newest text is on disk")
        NoteDrafts.remove(id)
        check(!NoteDrafts.all().contains { $0.id == id }, "removed")
    }

    // The editor keeps a draft file from the first keystroke until the store has the text, and keeps it when the
    // store couldn't write.
    SelfTest.cases.append(("Reliability.editorDraftFile", {
        MainActor.assumeIsolated {
            let b = Bench()
            defer { b.cleanup() }
            let note = b.load("")
            b.type("hello")
            NoteDrafts.settle()
            check(NoteDrafts.all().first { $0.id == note.id }?.content == "hello", "a draft is on disk before the debounced save")
            b.spin(0.5)
            NoteDrafts.settle()
            check(b.store.note(note.id)?.content == "hello" && !NoteDrafts.all().contains { $0.id == note.id },
                  "the draft goes once the store has the text")
            b.store.setPageLimit(1)
            b.tv.insertText(String(repeating: " and more", count: 40_000), replacementRange: b.tv.selectedRange())
            b.spin(0.5)
            NoteDrafts.settle()
            check(b.store.unsavedNoteIDs.contains(note.id) && NoteDrafts.all().contains { $0.id == note.id },
                  "the disk refused the save: the draft stays")
            b.store.setPageLimit(0)
            b.type("!")
            b.spin(0.5)
            NoteDrafts.settle()
            check(b.store.unsavedNoteIDs.isEmpty && !NoteDrafts.all().contains { $0.id == note.id }, "and goes once it lands")
        }
    }))

    // Typing into a blank note and moving on within the 0.3 s save debounce: the note is kept with the typing
    // (it used to be deleted as "empty" from the stale copy).
    SelfTest.cases.append(("Reliability.switchNoteMidDebounce", {
        MainActor.assumeIsolated {
            let b = Bench()
            defer { b.cleanup() }
            let older = b.store.create(content: "an older note")
            let front = b.store.create(content: "")
            WindowPreview.reload()
            _ = WindowPreview.frameView(revealed: false, slotBar: .hidden)
            check(WindowPreview.currentNoteID == front.id, "starts on the blank front note")
            guard let tv = WindowPreview.window.firstResponder as? NSTextView else { return check(false, "the note's text has the focus") }
            tv.insertText("typed fast", replacementRange: tv.selectedRange())
            WindowPreview.navigate(.previous)   // to the older note, within the debounce
            check(b.store.note(front.id)?.content == "typed fast", "the typed note survives the switch: \(String(describing: b.store.note(front.id)?.content))")
            check(WindowPreview.currentNoteID == older.id, "and the older note is shown")
            // A note left truly blank is still dropped.
            WindowPreview.navigate(.next)
            guard let tv2 = WindowPreview.window.firstResponder as? NSTextView, WindowPreview.currentNoteID == front.id else {
                return check(false, "back on the front note")
            }
            tv2.selectAll(nil)
            tv2.insertText("", replacementRange: tv2.selectedRange())
            WindowPreview.navigate(.previous)
            check(b.store.note(front.id) == nil, "an emptied note is deleted when left")
        }
    }))

    // Links from other apps may not wipe a note quietly, and locked or read-only notes are left alone.
    SelfTest.cases.append(("Reliability.urlOverwriteKeepsOldText", {
        check(URLCommand.keepsCopy(of: "my notes", replacedBy: "theirs"), "different text: the old one is kept in The Void")
        check(!URLCommand.keepsCopy(of: "  \n", replacedBy: "theirs"), "a blank note has nothing to keep")
        check(!URLCommand.keepsCopy(of: "same", replacedBy: "same"), "the same text again keeps nothing")
        check(URLCommand.rejection(editing: Note(content: "x", isLocked: true)) == "This note is locked", "locked notes refuse")
        check(URLCommand.rejection(editing: Note(content: "x", isReadOnly: true)) == "This note is read-only", "read-only notes refuse")
        check(URLCommand.rejection(editing: Note(content: "x")) == nil, "ordinary notes accept")
    }))

    // Text that is easy to get wrong in storage: NUL bytes from a binary paste, emoji, combining marks, RTL,
    // and a 10 MB note, through the database and the JSON export.
    storageCase("oddTextRoundTrips") { dir in
        let s = try makeStore(dir)
        let samples = ["a\u{0}b\u{0}", "👩‍👩‍👧‍👦 🇳🇿 e\u{301} ﷽", "שלום עולם\u{200F} مرحبا", "\r\n\t\u{FEFF}", String(repeating: "0123456789", count: 1_000_000)]
        let ids = samples.map { s.create(content: $0).id }
        let reopened = try makeStore(dir)
        for (id, sample) in zip(ids, samples) {
            check(reopened.note(id)?.content == sample, "round trip of \(sample.prefix(12).debugDescription) (\(sample.utf8.count) bytes)")
        }
        let other = try makeStore(dir, "other")
        try other.importJSON(reopened.exportJSON())
        for (id, sample) in zip(ids, samples) { check(other.note(id)?.content == sample, "JSON round trip of \(sample.prefix(12).debugDescription)") }
    }

    // Every field survives export and import (dates to the second — the format is ISO 8601).
    storageCase("exportImportAllFields") { dir in
        let s = try makeStore(dir)
        let t = Date(timeIntervalSinceReferenceDate: 790_000_000)
        s.now = { t }
        let slotted = s.create(content: "slotted"), locked = s.create(content: "locked"), archived = s.create(content: "archived")
        let voided = s.create(content: "voided")
        s.setSlot(3, for: slotted.id)
        var l = s.note(locked.id)!
        l.isLocked = true; l.isReadOnly = true
        l.links = [ShortLink(url: "https://example.com/very/long", short: "example.com")]
        s.update(l)
        s.setArchived(true, for: archived.id)
        s.moveToVoid(voided.id)
        let other = try makeStore(dir, "other")
        let imported = try other.importJSON(s.exportJSON())
        check(imported == 4, "all four notes import")
        check(other.note(slotted.id)?.slot == 3, "slot")
        let ol = other.note(locked.id)
        check(ol?.isLocked == true && ol?.isReadOnly == true && ol?.links == l.links, "lock, read-only and links")
        check(other.note(archived.id)?.isArchived == true && other.archived.map(\.id) == [archived.id], "archive")
        check(other.note(voided.id)?.deletedAt.map { abs($0.timeIntervalSince(t)) < 1 } == true && other.void.map(\.id) == [voided.id], "The Void and its date")
        check(other.note(slotted.id).map { abs($0.created.timeIntervalSince(t)) < 1 && abs($0.modified.timeIntervalSince(t)) < 1 } == true, "created/modified")
        check((try? other.importJSON(Data("{\"format\":\"supernotes.notes\"".utf8))) == nil, "a truncated export is refused, not half-applied")
    }

    // The Void's retention and the unmodified-notes sweep never touch notes that aren't theirs.
    storageCase("retentionSparesLiveNotes") { dir in
        let s = try makeStore(dir)
        var clock = Date(timeIntervalSinceReferenceDate: 800_000_000)
        s.now = { clock }
        let old = s.create(content: "old but alive")
        let slotted = s.create(content: "slotted and old")
        s.setSlot(0, for: slotted.id)
        let archived = s.create(content: "archived and old")
        s.setArchived(true, for: archived.id)
        let voided = s.create(content: "voided")
        s.moveToVoid(voided.id)
        clock += 400 * 86_400
        s.purgeExpiredVoid(retentionDays: 30)
        check(s.note(old.id) != nil && s.note(slotted.id) != nil && s.note(archived.id) != nil && s.note(voided.id) == nil,
              "only the Void note older than the retention is purged")
        let cutoff = clock.addingTimeInterval(-30 * 86_400)
        check(s.note(old.id)!.isUnmodified(since: cutoff) && !s.note(slotted.id)!.isUnmodified(since: cutoff)
              && !s.note(archived.id)!.isUnmodified(since: cutoff), "the sweep takes only ephemeral deck notes")
        check(!s.deleteIfEmpty(old.id) && !s.deleteIfEmpty(UUID()), "deleteIfEmpty never deletes text or unknown ids")
        let marker = s.create(content: "[ ] ")
        check(!s.deleteIfEmpty(marker.id), "an empty checkbox is still content, kept")
    }

    // Preferences with the wrong type or out-of-range values never crash and fall back to the default.
    SelfTest.cases.append(("Reliability.settingsGarbage", {
        let suite = "supernotes.selftest.garbage.\(UUID().uuidString)"
        let saved = Defaults.store
        Defaults.store = UserDefaults(suiteName: suite)!
        defer { Defaults.store = saved; UserDefaults().removePersistentDomain(forName: suite) }
        let store = Defaults.store
        store.set("thirty", forKey: Defaults.Keys.voidRetentionDays.name)
        store.set(Data([0xFF, 0x00, 0x12]), forKey: Defaults.Keys.textSize.name)
        store.set(42, forKey: Defaults.Keys.suppressedWarnings.name)
        store.set(-3, forKey: Defaults.Keys.backupCount.name)
        store.set("slow", forKey: Defaults.Keys.vimMotionTimeout.name)
        check(Defaults[.voidRetentionDays] == 30, "a word in an Int key reads as the default")
        check(Defaults[.textSize] == .m, "garbage bytes in an enum key read as the default")
        check(Defaults[.suppressedWarnings].isEmpty, "a number in a set key reads as empty")
        check(max(Defaults[.backupCount], 1) == 1, "a negative backup count still keeps one")
        check(Defaults[.vimMotionTimeout] == 1000, "a word in a Double key reads as the default")
    }))
}
