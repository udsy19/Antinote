import Foundation
import JotterCore

/// Which notes Search lists: the swipeable deck or the slotted notes.
public enum SearchScope: String, Codable, Sendable {
    case ephemeral, slotted
}

/// The pure rules behind the Search pane: which notes match, how a note is previewed and dated.
public enum SearchModel {
    /// The query that browses archived notes instead of searching.
    public static let archivedQuery = "archived"

    /// Notes to show, front first (slotted notes by slot). An empty query lists everything in scope; the query
    /// "archived" lists archived notes.
    public static func results(query: String, scope: SearchScope, deck: [Note], archived: [Note]) -> [Note] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.lowercased() == archivedQuery { return archived }
        let pool = scope == .slotted
            ? deck.filter { $0.slot != nil }.sorted { ($0.slot ?? 0) < ($1.slot ?? 0) }
            : deck.filter { $0.slot == nil }
        guard !q.isEmpty else { return pool }
        return pool.filter { $0.content.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// The lines a preview shows: the keyword line is dropped (its title kept), list markers are removed and
    /// blank lines skipped.
    public static func previewLines(_ content: String) -> [String] {
        var lines = content.components(separatedBy: "\n")
        if let first = lines.first {
            let detected = NoteMode.detect(firstLine: first)
            if detected.mode != .plain {
                lines[0] = detected.arguments
            }
        }
        return lines.map(stripMarker).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// One-paragraph preview for the list view: lines joined with "  |  ".
    public static func listPreview(_ content: String) -> String {
        previewLines(content).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "  |  ")
    }

    /// "Edited 6 hours ago" within a day of `now`, otherwise the date ("August 12", with the year when it differs).
    public static func meta(modified: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if now.timeIntervalSince(modified) < 86_400 {
            let relative = RelativeDateTimeFormatter()
            relative.locale = locale
            relative.unitsStyle = .full
            relative.dateTimeStyle = .numeric
            let seconds = min(-1, modified.timeIntervalSince(now))
            return "Edited " + (seconds > -60 ? "just now" : relative.localizedString(fromTimeInterval: seconds))
        }
        let format = DateFormatter()
        format.locale = locale
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: modified) == calendar.component(.year, from: now)
        format.setLocalizedDateFormatFromTemplate(sameYear ? "MMMMd" : "MMMMdyyyy")
        return format.string(from: modified)
    }

    /// "[ ] milk" / "- [x] milk" → "milk" (indentation kept).
    static func stripMarker(_ line: String) -> String {
        guard let match = markerRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
        else { return line }
        return (line as NSString).replacingCharacters(in: match.range(at: 1), with: "")
    }

    private static let markerRegex = try! NSRegularExpression(pattern: #"^\s*((?:[-*] )?\[[ xX]?\] ?)"#)
}
