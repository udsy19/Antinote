import AppKit

/// One note's undo history for the session. Every step keeps the whole editor state (text, selection, links)
/// before and after, so undo and redo put back exactly what was there and never depend on range bookkeeping
/// while the editor rewrites list markers, shortens links or runs commands in the middle of a keystroke.
/// Typing coalesces into one step per word (`TypingCoalescing`); every named edit is a step of its own.
@MainActor
final class NoteHistory {
    struct Snapshot {
        var text: String
        var selection: NSRange
        var links: [TrackedLink]
        var allLinksExpanded: Bool
    }

    final class Step {
        var before: Snapshot
        var after: Snapshot
        let name: String
        /// Plain typing: later keystrokes may extend this step.
        let typing: Bool
        var typedAt: Date

        init(before: Snapshot, after: Snapshot, name: String, typing: Bool, at date: Date = Date()) {
            self.before = before; self.after = after; self.name = name; self.typing = typing; typedAt = date
        }
    }

    static let levels = 200

    let manager = UndoManager()
    /// The editor's state after the last recorded change: what the next step starts from.
    var committed: Snapshot
    /// The step registered last, while nothing was undone or loaded since (typing extends it; a list marker
    /// rewrite folds into it).
    var last: Step?

    init(_ snapshot: Snapshot) {
        committed = snapshot
        manager.levelsOfUndo = Self.levels
        manager.groupsByEvent = false
    }

    /// Forgets every step; the editor starts afresh from `snapshot`.
    func reset(to snapshot: Snapshot) {
        manager.removeAllActions()
        last = nil
        committed = snapshot
    }
}

/// When a keystroke extends the step before it (self-tested).
public enum TypingCoalescing {
    /// Keystrokes further apart than this start a new step.
    public static let pause: TimeInterval = 2

    /// Whether a keystroke turning the step's text `old` (caret at `caret`) into `new` joins a step that so far
    /// typed `typed` (what the step inserted; empty for deletions): one character in at the caret or out next to
    /// it, not after a line break, and a space never joins a word. Checked against the caret, not a text diff,
    /// which slides across repeated characters ("Oh" + "h").
    public static func extends(typed: String, caret: Int, old: String, new: String, elapsed: TimeInterval) -> Bool {
        guard elapsed < pause, typed.last != "\n" else { return false }
        let a = old as NSString, b = new as NSString
        switch b.length - a.length {
        case 1:
            guard caret <= a.length, b.substring(to: caret) == a.substring(to: caret),
                  b.substring(from: caret + 1) == a.substring(from: caret) else { return false }
            let char = b.substring(with: NSRange(location: caret, length: 1))
            let space = char.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
            return !(space && typed.last.map { !$0.isWhitespace } == true)
        case -1:
            return deletes(a, at: caret - 1, giving: b) || deletes(a, at: caret, giving: b)
        default:
            return false
        }
    }

    /// Where typing leaves the caret: after what replaced the selection `before`, which turned `old` into `new`
    /// (`live`, the text view's own caret, wins when it fits — it tells forward delete from backspace).
    public static func caretAfter(before: NSRange, old: String, new: String, live: Int) -> Int {
        let delta = (new as NSString).length - (old as NSString).length
        var candidates = [max(0, before.location + before.length + delta)]
        if delta < 0, before.length == 0 { candidates.append(before.location) }   // forward delete
        return candidates.contains(live) ? live : candidates[0]
    }

    private static func deletes(_ a: NSString, at index: Int, giving b: NSString) -> Bool {
        index >= 0 && index < a.length && b.isEqual(to: a.replacingCharacters(in: NSRange(location: index, length: 1), with: ""))
    }
}
