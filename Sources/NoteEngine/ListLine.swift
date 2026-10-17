import Foundation
import JotterCore

/// A line split into indentation, list marker and text: `\t[ ] buy milk`, `- item`, `2. step`.
public struct ListLine: Equatable, Sendable {
    public enum Marker: Equatable, Sendable {
        /// `[ ]` / `[x]`; `dashed` for the markdown task form `- [ ]`.
        case checkbox(checked: Bool, dashed: Bool = false)
        /// `-`, `*`, `•` or `+`.
        case bullet(Character)
        /// `1.` or `1)`.
        case numbered(Int, delimiter: Character = ".")

        public var text: String {
            switch self {
            case let .checkbox(checked, dashed): (dashed ? "- " : "") + (checked ? "[x]" : "[ ]")
            case let .bullet(ch): String(ch)
            case let .numbered(n, delimiter): "\(n)\(delimiter)"
            }
        }
        public var style: ListStyle {
            switch self {
            case .checkbox: .checkbox
            case .bullet: .bullet
            case .numbered: .numbered
            }
        }
    }

    /// Leading whitespace, kept verbatim.
    public var indent: String
    public var marker: Marker?
    public var text: String

    public init(indent: String = "", marker: Marker?, text: String) {
        self.indent = indent; self.marker = marker; self.text = text
    }

    /// Nesting depth: one per tab, one per 4 spaces.
    public var level: Int {
        indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 4
    }

    /// Length (in characters) of indentation + marker + following space, i.e. where `text` starts.
    public var prefixLength: Int { formatted.count - text.count }

    public var formatted: String {
        guard let marker else { return indent + text }
        return indent + marker.text + " " + text
    }

    public var isChecked: Bool { if case .checkbox(true, _) = marker { true } else { false } }

    private static let bullets: Set<Character> = ["-", "*", "•", "+"]

    public static func parse(_ line: String) -> ListLine {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let rest = line.dropFirst(indent.count)
        func after(_ n: Int) -> String? {
            let tail = rest.dropFirst(n)
            if tail.isEmpty { return "" }
            guard tail.first == " " else { return nil }
            return String(tail.dropFirst())
        }
        for (dashed, prefix) in [(true, "- "), (false, "")] where rest.hasPrefix(prefix) {
            let box = rest.dropFirst(prefix.count)
            if box.count >= 3, box.first == "[", box.dropFirst(2).first == "]" {
                let mark = box.dropFirst().first!
                let checked = mark == "x" || mark == "X"
                if checked || mark == " ", let text = after(prefix.count + 3) {
                    return ListLine(indent: indent, marker: .checkbox(checked: checked, dashed: dashed), text: text)
                }
            }
        }
        // A bullet needs a following space: "- item" but not "-", "--" or "-5".
        if let first = rest.first, bullets.contains(first), rest.count > 1, let text = after(1) {
            return ListLine(indent: indent, marker: .bullet(first), text: text)
        }
        let digits = rest.prefix { $0.isASCIIDigit }
        if !digits.isEmpty, digits.count <= 4, let n = Int(digits), let delimiter = rest.dropFirst(digits.count).first,
           delimiter == "." || delimiter == ")", let text = after(digits.count + 1), rest.count > digits.count + 1 {
            return ListLine(indent: indent, marker: .numbered(n, delimiter: delimiter), text: text)
        }
        return ListLine(indent: indent, marker: nil, text: String(rest))
    }

    /// Checkbox → bullet → numbered → plain → `start` style (the default list style).
    public func cycled(start: ListStyle = .checkbox) -> ListLine {
        var copy = self
        switch marker {
        case .checkbox?: copy.marker = .bullet("-")
        case .bullet?: copy.marker = .numbered(1)
        case .numbered?: copy.marker = nil
        case nil: copy.marker = Self.marker(for: start)
        }
        return copy
    }

    /// Flips a checkbox; turns any other line into an unchecked checkbox.
    public func toggled() -> ListLine {
        var copy = self
        if case let .checkbox(checked, dashed)? = marker {
            copy.marker = .checkbox(checked: !checked, dashed: dashed)
        } else {
            copy.marker = .checkbox(checked: false)
        }
        return copy
    }

    /// The empty line that continues this list when Return is pressed (nil for plain lines).
    public func continuation() -> ListLine? {
        guard let marker else { return nil }
        switch marker {
        case let .checkbox(_, dashed): return ListLine(indent: indent, marker: .checkbox(checked: false, dashed: dashed), text: "")
        case .bullet: return ListLine(indent: indent, marker: marker, text: "")
        case let .numbered(n, d): return ListLine(indent: indent, marker: .numbered(n + 1, delimiter: d), text: "")
        }
    }

    public static func marker(for style: ListStyle) -> Marker {
        switch style {
        case .checkbox: .checkbox(checked: false)
        case .bullet: .bullet("-")
        case .numbered: .numbered(1)
        }
    }

    /// Renumbers runs of numbered lines (1, 2, 3…) per indentation level. A blank or non-list line, or a
    /// shallower line, ends a run.
    public static func renumber(_ lines: [String]) -> [String] {
        var counters: [Int: Int] = [:]   // level → last number
        return lines.map { raw in
            var line = parse(raw)
            guard let marker = line.marker else { counters.removeAll(); return raw }
            let level = line.level
            counters = counters.filter { $0.key <= level }
            if case let .numbered(_, d) = marker {
                let n = (counters[level] ?? 0) + 1
                counters[level] = n
                line.marker = .numbered(n, delimiter: d)
                return line.formatted
            }
            counters[level] = nil
            return raw
        }
    }
}
