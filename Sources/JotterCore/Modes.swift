import Foundation

/// What a note does, decided by the keyword on its first line ("list", "math", "timer"…).
public enum NoteMode: String, Codable, CaseIterable, Sendable {
    case plain, list, math, sum, average, count, timer, code, autopaste

    public var displayName: String {
        switch self {
        case .plain: "Plain text"
        case .list: "Checklist"
        case .math: "Math"
        case .sum: "Sum"
        case .average: "Average"
        case .count: "Count"
        case .timer: "Timer"
        case .code: "Code"
        case .autopaste: "AutoPaste"
        }
    }

    /// Built-in keywords. Users can add more per mode in Settings → Keywords (`Defaults[.extraKeywords]`).
    public var defaultKeywords: [String] {
        switch self {
        case .plain: []
        case .list: ["list", "todo", "checklist", "tasks"]
        case .math: ["math", "calc", "calculate"]
        case .sum: ["sum", "total"]
        case .average: ["avg", "average", "mean"]
        case .count: ["count", "wc"]
        case .timer: ["timer", "stopwatch", "countdown", "pomodoro"]
        case .code: ["code", "snippet"]
        case .autopaste: ["paste", "autopaste"]
        }
    }

    public var keywords: [String] {
        defaultKeywords + (Defaults[.extraKeywords][rawValue] ?? [])
    }

    /// Detects the mode from the first line: the line must consist of a keyword, optionally followed by arguments
    /// (e.g. `timer 25m`, `pomodoro 25 5`). Matching is case-insensitive.
    public static func detect(firstLine: String) -> (mode: NoteMode, keyword: String, arguments: String) {
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        // "list: Groceries" — a colon right after the keyword introduces a title.
        let token = trimmed.prefix { !$0.isWhitespace && $0 != ":" }
        let word = token.lowercased()
        guard !word.isEmpty else { return (.plain, "", "") }
        for mode in NoteMode.allCases where mode != .plain {
            if mode.keywords.contains(where: { $0.lowercased() == word }) {
                var rest = trimmed.dropFirst(token.count)
                if rest.first == ":" { rest = rest.dropFirst() }
                let args = rest.trimmingCharacters(in: .whitespaces)
                return (mode, word, args)
            }
        }
        return (.plain, "", "")
    }
}

/// Result of analysing a note for display: per-line annotations (math results, errors) and an optional summary
/// (sum/average/count). Produced by `Services.analyzer`, rendered by the editor.
public struct NoteAnalysis: Sendable, Equatable {
    public var mode: NoteMode
    /// Arguments after the keyword on the first line (e.g. "25m" for `timer 25m`).
    public var arguments: String
    public var annotations: [LineAnnotation]
    /// e.g. "Total: 1,240" / "Average: 12.5" / "12 lines · 87 words · 512 characters".
    public var summary: String?
    /// Math variables: 0-based line index → the (lowercased) name that line defines.
    public var definitions: [Int: String]

    public init(mode: NoteMode, arguments: String = "", annotations: [LineAnnotation] = [], summary: String? = nil,
                definitions: [Int: String] = [:]) {
        self.mode = mode; self.arguments = arguments; self.annotations = annotations; self.summary = summary
        self.definitions = definitions
    }
    public static let plain = NoteAnalysis(mode: .plain)
}

public struct LineAnnotation: Sendable, Equatable {
    public enum Kind: String, Sendable { case result, error, info }
    /// 0-based line index in the note.
    public var line: Int
    /// Text drawn right after the line's end (e.g. "42", "€38.20").
    public var text: String
    public var kind: Kind
    /// Numeric value, when the line produced one (used by sums and variables).
    public var value: Double?
    public init(line: Int, text: String, kind: Kind = .result, value: Double? = nil) {
        self.line = line; self.text = text; self.kind = kind; self.value = value
    }
}

/// Pure text logic for note modes (math engine, sums, counts, list markers, link shrinking, paste cleaning).
public protocol NoteAnalyzing: AnyObject {
    func analyze(_ text: String) -> NoteAnalysis
    /// Evaluates a standalone expression (used by the extension `MathEvaluator` bridge).
    func evaluate(_ expression: String) -> Result<Double, Error>
    /// Cleans pasted text per Settings → Copy & Paste (strip formatting/markdown, bullets, numbering, indentation).
    func cleanPaste(_ text: String) -> String
    /// Shortens a URL for display (keeps a readable ending), e.g. `github.com/…/pull/42`.
    func shorten(url: String) -> String
}
