import Foundation
import JotterCore

/// Pure text preparation for exports.
public enum ExportText {
    /// The note's text with the keyword line removed when `omitKeyword` is set and the first line is a keyword.
    public static func body(_ content: String, omitKeyword: Bool) -> String {
        guard omitKeyword else { return content }
        let lines = content.components(separatedBy: "\n")
        guard let first = lines.first, NoteMode.detect(firstLine: first).mode != .plain else { return content }
        return lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    /// First non-empty line, or "Untitled".
    public static func title(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        return line.map { String($0.prefix(120)) } ?? "Untitled"
    }

    /// A file name for `title` without extension (no path separators or colons, at most 80 characters).
    public static func baseName(_ title: String) -> String {
        let cleaned = title.map { "/:\\\0".contains($0) ? "-" : $0 }
        let base = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ".")))
        return base.isEmpty ? "Untitled" : String(base.prefix(80))
    }

    public static func fileName(_ title: String, ext: String) -> String { baseName(title) + "." + ext }

    private static let unchecked = ["☐", "◻", "□", "[ ]", "- [ ]", "* [ ]"]
    private static let checked = ["☑", "☒", "✓", "✔", "[x]", "[X]", "- [x]", "- [X]", "* [x]"]
    private static let bullets = ["•", "◦", "‣", "▪", "–", "*"]

    /// Converts Jotter's plain-text list markers to Markdown. `isChecklist` (list-mode notes) turns unmarked lines
    /// into open tasks. Indentation is preserved.
    public static func markdown(_ text: String, isChecklist: Bool = false) -> String {
        text.components(separatedBy: "\n").map { line -> String in
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            let rest = line.dropFirst(indent.count)
            guard !rest.isEmpty else { return line }
            if let item = strip(rest, markers: checked) { return indent + "- [x] " + item }
            if let item = strip(rest, markers: unchecked) { return indent + "- [ ] " + item }
            if let item = strip(rest, markers: bullets) { return indent + (isChecklist ? "- [ ] " : "- ") + item }
            return isChecklist ? indent + "- [ ] " + rest : line
        }.joined(separator: "\n")
    }

    private static func strip(_ line: Substring, markers: [String]) -> String? {
        // Longest marker first so "- [ ]" wins over "-".
        for marker in markers.sorted(by: { $0.count > $1.count }) where line.hasPrefix(marker) {
            let after = line.dropFirst(marker.count)
            if after.isEmpty { return "" }
            if after.first == " " { return String(after.dropFirst()) }
        }
        return nil
    }

    /// The Markdown file content for a note: keyword handling plus marker conversion. Checklist notes (list mode)
    /// turn every item line into a task; a kept keyword line stays as is.
    public static func markdownDocument(_ content: String, omitKeyword: Bool) -> String {
        let lines = content.components(separatedBy: "\n")
        let isChecklist = NoteMode.detect(firstLine: lines.first ?? "").mode == .list
        let body = Self.body(content, omitKeyword: omitKeyword)
        if isChecklist && body == content {
            return ([lines[0]] + [markdown(lines.dropFirst().joined(separator: "\n"), isChecklist: true)])
                .joined(separator: "\n")
        }
        return markdown(body, isChecklist: isChecklist)
    }

    /// Minimal HTML for Apple Notes: escaped text, one `<div>` per line.
    public static func html(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            let escaped = line.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return "<div>\(escaped.isEmpty ? "<br>" : escaped)</div>"
        }.joined()
    }

    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Percent-encodes a URL query value (everything but unreserved characters).
    public static func queryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
