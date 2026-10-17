import Foundation
import Combine

/// A single plain-text note.
///
/// Notes form one ordered stack ("the deck") that you swipe through; `position` 0 is the front (most recent).
/// A note can additionally sit in one of the numbered *slots* (pinned quick-access notes shown in the slots bar).
public struct Note: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var content: String
    public var created: Date
    public var modified: Date
    /// Position in the deck; 0 = front. Unique among non-deleted notes.
    public var position: Int
    /// Slot index (0-based) when the note is slotted, otherwise nil.
    public var slot: Int?
    public var isLocked: Bool
    public var isReadOnly: Bool
    public var isArchived: Bool
    /// Moved to The Void (recoverable trash) at this date.
    public var deletedAt: Date?
    /// Shortened links in this note: the visible short text ↔ the full URL.
    public var links: [ShortLink]

    public init(id: UUID = UUID(), content: String = "", created: Date = Date(), modified: Date = Date(),
                position: Int = 0, slot: Int? = nil, isLocked: Bool = false, isReadOnly: Bool = false,
                isArchived: Bool = false, deletedAt: Date? = nil, links: [ShortLink] = []) {
        self.id = id; self.content = content; self.created = created; self.modified = modified
        self.position = position; self.slot = slot; self.isLocked = isLocked; self.isReadOnly = isReadOnly
        self.isArchived = isArchived; self.deletedAt = deletedAt; self.links = links
    }

    public var isInVoid: Bool { deletedAt != nil }
    /// Whether "Delete all notes not modified since" / "Auto-delete unmodified notes" take this note: an ephemeral,
    /// unarchived note outside The Void last changed before `date`.
    public func isUnmodified(since date: Date) -> Bool {
        slot == nil && !isArchived && !isInVoid && modified < date
    }
    /// First non-empty line, used as a title in lists and exports.
    public var title: String {
        content.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }
}

/// A shortened link ("Link Shrink"): `short` is what's displayed in the text, `url` the full address.
public struct ShortLink: Codable, Hashable, Sendable {
    public var url: String
    public var short: String
    public init(url: String, short: String) { self.url = url; self.short = short }
}

public enum NoteStoreChange: Sendable {
    case inserted(UUID), updated(UUID), removed(UUID), reordered, reloaded
}

/// Persistence for notes (SQLite, implemented in StorageKit). All calls are main-actor and synchronous —
/// notes are small and the database is local.
@MainActor
public protocol NoteStoring: AnyObject {
    /// Non-deleted, non-archived notes ordered by `position` (front first). Includes slotted notes.
    var deck: [Note] { get }
    /// Notes currently in The Void, most recently deleted first.
    var void: [Note] { get }
    var archived: [Note] { get }
    func note(_ id: UUID) -> Note?

    /// Creates a note at the front of the deck.
    @discardableResult func create(content: String) -> Note
    /// Saves content/flags/links. Updates `modified` when content changed.
    func update(_ note: Note)
    func moveToVoid(_ id: UUID)
    func restoreFromVoid(_ id: UUID)
    func deletePermanently(_ id: UUID)
    /// Deletes Void notes older than the retention period (Settings) — called at launch and hourly.
    func purgeExpiredVoid()
    func promoteToFront(_ id: UUID)
    func move(_ id: UUID, toPosition: Int)
    func setSlot(_ slot: Int?, for id: UUID)
    func setArchived(_ archived: Bool, for id: UUID)
    /// Case-insensitive full-text search over the deck (and optionally archived notes).
    func search(_ query: String, includeArchived: Bool) -> [Note]

    var changes: AnyPublisher<NoteStoreChange, Never> { get }
    /// Deletes the note when its content is blank; returns whether it was deleted. Called when leaving a note.
    @discardableResult func deleteIfEmpty(_ id: UUID) -> Bool

    // Portable export/import of every note (JSON).
    func exportJSON() -> Data
    /// Merges notes by id (newer `modified` wins). Returns the number of notes imported or updated.
    @discardableResult func importJSON(_ data: Data) throws -> Int

    // Backups
    func backup() throws -> URL
    var backups: [URL] { get }
    /// Replaces the database with a backup (the app restarts afterwards).
    func restore(from backup: URL) throws
}
