import Foundation
import SuperNotesCore

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

/// Sizes of the Search pane. Its text runs one size step below the editor's (XS and S share the smallest step) and
/// doubles with "Double font size"; paddings grow with the size preset.
public enum SearchMetrics {
    private static let steps: [CGFloat] = [10, 12, 14, 16, 18]

    private static func step(_ size: TextSize) -> Int { TextSize.allCases.firstIndex(of: size) ?? 2 }

    /// Search field, list results and toolbar labels: XS/S 10, M 12, L 14, XL 16 pt.
    public static func textSize(_ size: TextSize, doubled: Bool) -> CGFloat {
        steps[max(0, step(size) - 1)] * (doubled ? 2 : 1)
    }

    /// The "Edited 6 hours ago" line: XS–M 10, L 12, XL 14 pt.
    public static func metaSize(_ size: TextSize, doubled: Bool) -> CGFloat {
        steps[max(0, step(size) - 2)] * (doubled ? 2 : 1)
    }

    /// Card text keeps the smallest step (10 pt, 20 when doubled).
    public static func cardTextSize(doubled: Bool) -> CGFloat { steps[0] * (doubled ? 2 : 1) }

    /// Vertical padding of the search field and of list rows: 8, 10, 12, 14, 16 pt.
    public static func rowPadding(_ size: TextSize) -> CGFloat { CGFloat(8 + 2 * step(size)) }

    /// Promote/delete glyph size; the buttons are 12 pt larger, square.
    public static func iconSize(doubled: Bool) -> CGFloat { doubled ? 20 : 10 }

    /// Card grid: columns at least 230 and at most 340 pt wide, 12 pt apart, as many as fit `width`.
    public static func cardColumns(width: CGFloat) -> (count: Int, width: CGFloat) {
        let spacing: CGFloat = 12, minimum: CGFloat = 230, maximum: CGFloat = 340
        let count = max(1, Int(((width + spacing) / (minimum + spacing)).rounded(.down)))
        let column = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        return (count, min(maximum, max(0, column)).rounded(.down))
    }
}

/// The Search pane's toolbar capsules sit on the window's bottom row (`ChromeMetrics`): 10 pt in from the sides,
/// centred 20 pt above the bottom, at least 30 pt tall, 8 pt apart. Where the two capsules with their labels
/// don't fit the width, the left capsule's items keep their glyphs and drop their labels.
public enum SearchToolbarLayout {
    public static let gap: CGFloat = 8
    /// Results scroll clear of the capsules.
    public static var resultsBottom: CGFloat { ChromeMetrics.row + ChromeMetrics.button / 2 + 20 }

    /// Whether the labels fit a pane `width` wide: `labelled` is the left capsule's width with its labels, `right`
    /// the right capsule's.
    public static func showsLabels(width: CGFloat, labelled: CGFloat, right: CGFloat) -> Bool {
        2 * ChromeMetrics.sideInset + labelled + gap + right <= width
    }
}
