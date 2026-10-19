import Foundation

/// The editor's write-ahead copy of the note being typed: `Drafts/<note id>.json` under Application Support holds
/// the text after every change and goes away once the store has written it. After a crash, a forced quit or a
/// power cut the next launch finds the file and puts the text back ("Recovered unsaved text").
///
/// Writes are atomic and coalesced on one background queue: a burst of keystrokes writes the newest text once.
public enum NoteDrafts {
    public struct Draft: Codable, Equatable, Sendable {
        public var id: UUID
        public var content: String
        public var links: [ShortLink]
        public var written: Date
        public init(id: UUID, content: String, links: [ShortLink] = [], written: Date = Date()) {
            self.id = id; self.content = content; self.links = links; self.written = written
        }
    }

    public static var folder: URL { SuperNotesPaths.ensure(SuperNotesPaths.support.appendingPathComponent("Drafts", isDirectory: true)) }

    private static let queue = DispatchQueue(label: "supernotes.drafts", qos: .utility)
    private static let lock = NSLock()
    /// The newest draft per note still to be written; a queued write that finds nothing here was superseded.
    nonisolated(unsafe) private static var pending: [UUID: Draft] = [:]

    private static func file(_ id: UUID, in folder: URL) -> URL { folder.appendingPathComponent("\(id.uuidString).json") }

    /// Records `draft` for writing.
    public static func write(_ draft: Draft) {
        let folder = self.folder
        lock.withLock { pending[draft.id] = draft }
        queue.async {
            guard let latest = lock.withLock({ pending.removeValue(forKey: draft.id) }) else { return }
            do {
                try JSONEncoder().encode(latest).write(to: file(draft.id, in: folder), options: .atomic)
            } catch {
                Log.store.error("draft write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Drops the draft of a note the store has written (queued after any write in flight).
    public static func remove(_ id: UUID) {
        let folder = self.folder
        lock.withLock { pending[id] = nil }
        queue.async { try? FileManager.default.removeItem(at: file(id, in: folder)) }
    }

    /// Every draft on disk, after queued writes have landed.
    public static func all() -> [Draft] {
        let folder = self.folder
        return queue.sync {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "json" }.compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Draft.self, from: data)
            }
        }
    }

    /// Waits for queued writes and removals (tests, and before the process exits).
    public static func settle() { queue.sync {} }
}
