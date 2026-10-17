import Foundation
import SuperNotesCore

// The store side of sync: snapshots for merging and applying a merge result.
extension SQLiteNoteStore {
    /// All notes in their synced form (deck position and slot are per-Mac, so they are blanked).
    func syncSnapshot() -> [UUID: NoteRecord] {
        records.mapValues { r in
            var r = r
            r.note.position = 0
            r.note.slot = nil
            return r
        }
    }

    /// `changed` of each note at its last successful sync.
    func syncBase() -> [UUID: Date] {
        let rows = (try? db.query("SELECT id, synced_changed FROM sync_state") { r in
            (UUID(uuidString: r.text(0)), Date(timeIntervalSinceReferenceDate: r.double(1)))
        }) ?? []
        return Dictionary(rows.compactMap { id, d in id.map { ($0, d) } }, uniquingKeysWith: { a, _ in a })
    }

    /// Applies remote winners and conflict copies, deletes notes removed elsewhere, and stores the new base.
    func applySync(_ plan: SyncPlan, keepingBaseOf pending: Set<UUID>) {
        var touched: [UUID] = []
        var inserted: [UUID] = []
        var updated: [UUID] = []
        for incoming in plan.apply {
            var r = incoming
            if let existing = records[r.note.id] {
                r.note.position = existing.note.position
                r.note.slot = existing.note.slot
                updated.append(r.note.id)
            } else {
                r.note.position = -1
                r.note.slot = nil
                inserted.append(r.note.id)
            }
            if r.note.deletedAt != nil || r.note.isArchived { r.note.slot = nil }
            records[r.note.id] = r
            touched.append(r.note.id)
        }
        let deleted = plan.delete.filter { records[$0] != nil }
        for id in deleted { records[id] = nil }

        // New active notes go to the front, newest first.
        let fresh = inserted.filter { records[$0].map { $0.note.deletedAt == nil && !$0.note.isArchived } ?? false }
            .sorted { records[$0]!.note.modified > records[$1]!.note.modified }
        let order = fresh + records.values.filter { $0.note.deletedAt == nil && !$0.note.isArchived && !fresh.contains($0.note.id) }
            .sorted { $0.note.position < $1.note.position }.map(\.note.id)
        persist(touched + renumber(deckOrder: order), removed: deleted)

        let kept = syncBase().filter { pending.contains($0.key) }
        do {
            try db.transaction {
                try db.execute("DELETE FROM sync_state")
                for (id, date) in plan.base.merging(kept, uniquingKeysWith: { _, old in old }) {
                    try db.run("INSERT INTO sync_state (id, synced_changed) VALUES (?, ?)", [.text(id.uuidString), .date(date)])
                }
            }
        } catch {
            Log.sync.error("saving sync state failed: \(error.localizedDescription, privacy: .public)")
        }

        inserted.forEach { subject.send(.inserted($0)) }
        updated.forEach { subject.send(.updated($0)) }
        deleted.forEach { subject.send(.removed($0)) }
    }
}
