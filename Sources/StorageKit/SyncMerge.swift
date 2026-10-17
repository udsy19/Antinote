import Foundation
import SuperNotesCore

/// What the sync folder holds for one note id.
public enum RemoteEntry: Equatable, Sendable {
    case note(NoteRecord)
    case tombstone(Date)
}

/// The outcome of merging local notes with the sync folder.
public struct SyncPlan: Equatable, Sendable {
    /// Records to write to the folder.
    public var push: [NoteRecord] = []
    /// Ids to replace with tombstones in the folder.
    public var tombstones: [UUID] = []
    /// Records to insert or update locally (remote winners and conflict copies).
    public var apply: [NoteRecord] = []
    /// Ids to delete locally (deleted on another Mac).
    public var delete: [UUID] = []
    /// `changed` of every note both sides agree on after this sync.
    public var base: [UUID: Date] = [:]
    public var conflicts = 0

    public var isEmpty: Bool { push.isEmpty && tombstones.isEmpty && apply.isEmpty && delete.isEmpty }
}

public enum SyncMerge {
    /// Merges per note id.
    /// - Only one side changed since the last sync (`base`) → that side wins.
    /// - Both changed → the newer `changed` wins; if the texts differ the older version is kept as a new note whose
    ///   first line is a "Sync conflict" header.
    /// - A tombstone deletes the local note unless it was edited after the last sync (and vice versa).
    /// - `localWins` (after restoring a backup): local notes overwrite the folder and remote-only notes are removed.
    public static func plan(local: [UUID: NoteRecord], remote: [UUID: RemoteEntry], base: [UUID: Date],
                     localWins: Bool = false, now: Date) -> SyncPlan {
        var plan = SyncPlan()
        let ids = Set(local.keys).union(remote.keys).union(base.keys)
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            let l = local[id], r = remote[id], b = base[id]
            if localWins {
                if let l {
                    if r != .note(l) { plan.push.append(l) }
                    plan.base[id] = l.changed
                } else if case .note = r {
                    plan.tombstones.append(id)
                }
                continue
            }
            switch (l, r) {
            case (nil, nil), (nil, .tombstone?):
                break
            case let (l?, nil):
                plan.push.append(l)
                plan.base[id] = l.changed
            case let (nil, .note(r)?):
                if let b, r.changed <= b {
                    plan.tombstones.append(id)          // deleted here, untouched there
                } else {
                    plan.apply.append(r)
                    plan.base[id] = r.changed
                }
            case (let l?, .tombstone?):
                if let b, l.changed <= b {
                    plan.delete.append(id)              // deleted there, untouched here
                } else {
                    plan.push.append(l)                 // edited here after the deletion: keep it
                    plan.base[id] = l.changed
                }
            case let (l?, .note(r)?):
                if l == r { plan.base[id] = l.changed; continue }
                let localChanged = b.map { l.changed > $0 } ?? true
                let remoteChanged = b.map { r.changed > $0 } ?? true
                let localIsWinner: Bool
                if localChanged != remoteChanged {
                    localIsWinner = localChanged
                } else {
                    localIsWinner = l.changed >= r.changed
                    if localChanged && l.note.content != r.note.content {
                        let loser = localIsWinner ? r : l
                        let copy = conflictCopy(of: loser.note, fromThisMac: !localIsWinner, now: now)
                        plan.apply.append(copy)
                        plan.push.append(copy)
                        plan.base[copy.note.id] = copy.changed
                        plan.conflicts += 1
                    }
                }
                if localIsWinner { plan.push.append(l); plan.base[id] = l.changed }
                else { plan.apply.append(r); plan.base[id] = r.changed }
            }
        }
        return plan
    }

    static func conflictCopy(of note: Note, fromThisMac: Bool, now: Date) -> NoteRecord {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        let header = "Sync conflict — version from \(fromThisMac ? "this Mac" : "another Mac"), \(f.string(from: note.modified))"
        var copy = note
        copy.id = UUID()
        copy.content = header + "\n" + note.content
        copy.modified = now
        copy.slot = nil
        copy.deletedAt = nil
        copy.isArchived = false
        return NoteRecord(note: copy, changed: now)
    }
}
