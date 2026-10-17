import Foundation
import JotterCore

/// Pure text transforms behind the editor (no AppKit), so they can be tested headlessly.
/// All offsets are UTF-16 (`NSString`/`NSRange`), matching `NSTextView`.
public enum EditorLogic {}

/// Text plus selection — the input and output of every editor transform.
public struct TextState: Equatable {
    public var text: String
    public var selection: NSRange
    public init(_ text: String, _ selection: NSRange = NSRange(location: 0, length: 0)) {
        self.text = text; self.selection = selection
    }
    public init(_ text: String, caret: Int) { self.init(text, NSRange(location: caret, length: 0)) }
    var ns: NSString { text as NSString }
}

// MARK: - Lines

extension EditorLogic {
    public enum Lines {
        private static let newline: unichar = 10

        /// Content ranges (without "\n") of every line; a trailing "\n" yields a final empty line.
        public static func ranges(_ s: NSString) -> [NSRange] {
            var out: [NSRange] = []
            var start = 0
            for i in 0..<s.length where s.character(at: i) == newline {
                out.append(NSRange(location: start, length: i - start)); start = i + 1
            }
            out.append(NSRange(location: start, length: s.length - start))
            return out
        }

        /// Content range of the line containing `location`.
        public static func range(_ s: NSString, at location: Int) -> NSRange {
            let loc = min(max(location, 0), s.length)
            var start = loc
            while start > 0, s.character(at: start - 1) != newline { start -= 1 }
            var end = loc
            while end < s.length, s.character(at: end) != newline { end += 1 }
            return NSRange(location: start, length: end - start)
        }

        public static func index(_ s: NSString, at location: Int) -> Int {
            let loc = min(max(location, 0), s.length)
            var n = 0
            for i in 0..<loc where s.character(at: i) == newline { n += 1 }
            return n
        }

        /// Indices of the lines a selection touches (a selection ending right after a newline excludes the next line).
        public static func covered(_ s: NSString, _ sel: NSRange) -> ClosedRange<Int> {
            let first = index(s, at: sel.location)
            var endLoc = sel.location + sel.length
            if sel.length > 0, endLoc > 0, endLoc <= s.length, s.character(at: endLoc - 1) == newline { endLoc -= 1 }
            return first...max(first, index(s, at: endLoc))
        }

        static func block(_ s: NSString, _ lines: ClosedRange<Int>) -> NSRange {
            let r = ranges(s)
            return NSRange(location: r[lines.lowerBound].location,
                           length: NSMaxRange(r[lines.upperBound]) - r[lines.lowerBound].location)
        }

        /// Swaps the selected lines with the line above/below. Nil at the edge.
        public static func move(_ st: TextState, up: Bool) -> TextState? {
            let s = st.ns, r = ranges(s), lines = covered(s, st.selection)
            if up ? lines.lowerBound == 0 : lines.upperBound == r.count - 1 { return nil }
            let blk = block(s, lines), blockText = s.substring(with: blk)
            let other = r[up ? lines.lowerBound - 1 : lines.upperBound + 1], otherText = s.substring(with: other)
            let replaced = up ? NSRange(location: other.location, length: NSMaxRange(blk) - other.location)
                              : NSRange(location: blk.location, length: NSMaxRange(other) - blk.location)
            let text = s.replacingCharacters(in: replaced, with: up ? blockText + "\n" + otherText : otherText + "\n" + blockText)
            let shift = up ? -(other.length + 1) : other.length + 1
            return TextState(text, NSRange(location: st.selection.location + shift, length: st.selection.length))
        }

        /// Duplicates the selected lines above or below; the selection follows the copy when duplicating down.
        public static func duplicate(_ st: TextState, up: Bool) -> TextState {
            let s = st.ns, blk = block(s, covered(s, st.selection)), blockText = s.substring(with: blk)
            if up {
                return TextState(s.replacingCharacters(in: NSRange(location: blk.location, length: 0), with: blockText + "\n"),
                                 st.selection)
            }
            return TextState(s.replacingCharacters(in: NSRange(location: NSMaxRange(blk), length: 0), with: "\n" + blockText),
                             NSRange(location: st.selection.location + blk.length + 1, length: st.selection.length))
        }

        /// Toggles `~~…~~` around the selection, or around the current line's content (after any list marker).
        public static func strikethrough(_ st: TextState) -> TextState? {
            let s = st.ns
            var target = st.selection
            if target.length == 0 {
                let line = range(s, at: target.location)
                let marker = ListLine.parse(s.substring(with: line)).map { ($0.indent as NSString).length + $0.markerLength }
                    ?? leadingWhitespace(s.substring(with: line))
                target = NSRange(location: line.location + marker, length: line.length - marker)
                guard target.length > 0 else { return nil }
            }
            let inner = s.substring(with: target)
            // Already wrapped inside the target, or the target sits between the tildes.
            if inner.count >= 4, inner.hasPrefix("~~"), inner.hasSuffix("~~") {
                let stripped = String(inner.dropFirst(2).dropLast(2))
                return TextState(s.replacingCharacters(in: target, with: stripped),
                                 NSRange(location: target.location, length: st.selection.length == 0 ? 0 : (stripped as NSString).length))
            }
            if target.location >= 2, NSMaxRange(target) + 2 <= s.length,
               s.substring(with: NSRange(location: target.location - 2, length: 2)) == "~~",
               s.substring(with: NSRange(location: NSMaxRange(target), length: 2)) == "~~" {
                let outer = NSRange(location: target.location - 2, length: target.length + 4)
                return TextState(s.replacingCharacters(in: outer, with: inner),
                                 NSRange(location: target.location - 2, length: st.selection.length))
            }
            let text = s.replacingCharacters(in: target, with: "~~" + inner + "~~")
            let sel = st.selection.length == 0 ? NSRange(location: st.selection.location + (st.selection.location >= target.location ? 2 : 0), length: 0)
                                               : NSRange(location: target.location + 2, length: target.length)
            return TextState(text, sel)
        }

        static func leadingWhitespace(_ line: String) -> Int {
            (line.prefix { $0 == " " || $0 == "\t" } as Substring).utf16.count
        }

        /// Applies `transform` to each listed line. Marker changes happen at line starts, so positions inside a
        /// line shift by that line's length delta (clamped to the line).
        public static func transform(_ st: TextState, lines: ClosedRange<Int>, _ f: (String) -> String) -> TextState {
            let s = st.ns, r = ranges(s)
            var out = "", deltaBefore = 0
            var newStart = st.selection.location, newEnd = NSMaxRange(st.selection)
            var startMapped = false
            func map(_ p: Int, line: NSRange, newLength: Int, accumulated: Int) -> Int {
                let offset = p - line.location
                return line.location + accumulated + min(max(offset + (newLength - line.length), 0), newLength)
            }
            for (i, line) in r.enumerated() {
                let old = s.substring(with: line)
                let new = lines.contains(i) ? f(old) : old
                let newLen = (new as NSString).length
                if !startMapped, st.selection.location >= line.location && st.selection.location <= NSMaxRange(line) {
                    newStart = lines.contains(i) ? map(st.selection.location, line: line, newLength: newLen, accumulated: deltaBefore)
                                                 : st.selection.location + deltaBefore
                    startMapped = true
                }
                let end = NSMaxRange(st.selection)
                if end >= line.location && end <= NSMaxRange(line) {
                    newEnd = lines.contains(i) ? map(end, line: line, newLength: newLen, accumulated: deltaBefore) : end + deltaBefore
                }
                out += new
                if i < r.count - 1 { out += "\n" }
                deltaBefore += newLen - line.length
            }
            return TextState(out, NSRange(location: newStart, length: max(0, newEnd - newStart)))
        }
    }
}

// MARK: - List markers

/// A list line: optional indentation, a marker (`[ ]`, `[x]`, `- `, `* `, `• `, `1. `) and content.
public struct ListLine: Equatable {
    public enum Kind: Equatable { case checkbox(checked: Bool), bullet(Character), numbered(Int) }
    public var indent: String
    public var kind: Kind
    /// UTF-16 length of the marker including its trailing space (when present).
    public var markerLength: Int
    public var content: String

    public static func parse(_ line: String) -> ListLine? {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let rest = line.dropFirst(indent.count)
        func spaced(_ markerLen: Int) -> (Int, String)? {
            let after = rest.dropFirst(markerLen)
            if after.isEmpty { return (markerLen, "") }
            guard after.first == " " else { return nil }
            return (markerLen + 1, String(after.dropFirst()))
        }
        if rest.hasPrefix("[ ]") || rest.hasPrefix("[x]") || rest.hasPrefix("[X]"), let (len, content) = spaced(3) {
            return ListLine(indent: indent, kind: .checkbox(checked: rest.dropFirst().first != " "), markerLength: len, content: content)
        }
        if let c = rest.first, c == "-" || c == "*" || c == "•", rest.dropFirst().first == " " {
            return ListLine(indent: indent, kind: .bullet(c), markerLength: 2, content: String(rest.dropFirst(2)))
        }
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        if (1...3).contains(digits.count), rest.dropFirst(digits.count).first == ".", rest.dropFirst(digits.count + 1).first == " ",
           let n = Int(digits) {
            return ListLine(indent: indent, kind: .numbered(n), markerLength: digits.count + 2,
                            content: String(rest.dropFirst(digits.count + 2)))
        }
        return nil
    }

    public static func marker(_ kind: Kind) -> String {
        switch kind {
        case .checkbox(let checked): checked ? "[x] " : "[ ] "
        case .bullet(let c): "\(c) "
        case .numbered(let n): "\(n). "
        }
    }

    public var text: String { indent + ListLine.marker(kind) + content }
    public var isChecked: Bool { kind == .checkbox(checked: true) }
    /// Indentation width with tabs counted as four columns.
    public static func depth(_ indent: String) -> Int { indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } }
}

// MARK: - List editing

extension EditorLogic {
    public enum Lists {
        /// "Toggle Checklist Item": toggles a checkbox; turns any other line into an unchecked item.
        public static func toggled(_ line: String) -> String {
            if var l = ListLine.parse(line) {
                if case .checkbox(let checked) = l.kind { l.kind = .checkbox(checked: !checked) } else { l.kind = .checkbox(checked: false) }
                return l.text
            }
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            return indent + "[ ] " + line.dropFirst(indent.count)
        }

        /// ⌘⇧M: none → checkbox → bullet → numbered → checkbox.
        public static func cycled(_ line: String) -> String {
            guard var l = ListLine.parse(line) else { return toggled(line) }
            switch l.kind {
            case .checkbox: l.kind = .bullet("-")
            case .bullet: l.kind = .numbered(1)
            case .numbered: l.kind = .checkbox(checked: false)
            }
            return l.text
        }

        public static func indented(_ line: String) -> String { "\t" + line }

        public static func outdented(_ line: String) -> String {
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            let spaces = line.prefix(4).prefix { $0 == " " }.count
            return String(line.dropFirst(spaces))
        }

        public static func toggle(_ st: TextState) -> TextState {
            renumbered(Lines.transform(st, lines: Lines.covered(st.ns, st.selection), toggled))
        }

        public static func cycle(_ st: TextState) -> TextState {
            renumbered(Lines.transform(st, lines: Lines.covered(st.ns, st.selection), cycled))
        }

        public static func indent(_ st: TextState, outdent: Bool) -> TextState {
            renumbered(Lines.transform(st, lines: Lines.covered(st.ns, st.selection), outdent ? outdented : indented))
        }

        /// Return inside a list item: split it into a new item (unchecked / same bullet / next number), or — on an
        /// empty item — outdent it, or remove the marker at the top level. Nil when the caret line is not an item.
        public static func continued(_ st: TextState) -> TextState? {
            guard st.selection.length == 0 else { return nil }
            let s = st.ns, lineRange = Lines.range(s, at: st.selection.location)
            guard let item = ListLine.parse(s.substring(with: lineRange)) else { return nil }
            let markerEnd = lineRange.location + (item.indent as NSString).length + item.markerLength
            guard st.selection.location >= markerEnd else { return nil }
            if item.content.trimmingCharacters(in: .whitespaces).isEmpty {
                if !item.indent.isEmpty {
                    return indent(st, outdent: true)
                }
                return TextState(s.replacingCharacters(in: lineRange, with: ""), NSRange(location: lineRange.location, length: 0))
            }
            let next: ListLine.Kind
            switch item.kind {
            case .checkbox: next = .checkbox(checked: false)
            case .bullet(let c): next = .bullet(c)
            case .numbered(let n): next = .numbered(n + 1)
            }
            let insert = "\n" + item.indent + ListLine.marker(next)
            let text = s.replacingCharacters(in: st.selection, with: insert)
            return renumbered(TextState(text, NSRange(location: st.selection.location + (insert as NSString).length, length: 0)))
        }

        /// Renumbers consecutive numbered items per indentation level (a run keeps its first number).
        public static func renumber(_ text: String) -> String {
            var counters: [Int: Int] = [:]
            let lines = text.components(separatedBy: "\n").map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).isEmpty { counters.removeAll(); return line }
                let indent = String(line.prefix { $0 == " " || $0 == "\t" })
                let depth = ListLine.depth(indent)
                counters = counters.filter { $0.key <= depth }
                guard var item = ListLine.parse(line), case .numbered(let n) = item.kind else {
                    counters[depth] = nil; return line
                }
                let number = counters[depth] ?? n
                counters[depth] = number + 1
                item.kind = .numbered(number)
                return item.text
            }
            return lines.joined(separator: "\n")
        }

        static func renumbered(_ st: TextState) -> TextState {
            let text = renumber(st.text)
            guard text != st.text else { return st }
            // Renumbering only changes digits; map the selection through the minimal change.
            let change = EditorLogic.minimalChange(from: st.text, to: text)
            let delta = (change.replacement as NSString).length - change.range.length
            func map(_ p: Int) -> Int { p >= NSMaxRange(change.range) ? p + delta : p }
            let start = map(st.selection.location)
            return TextState(text, NSRange(location: start, length: max(0, map(NSMaxRange(st.selection)) - start)))
        }

        /// List notes: every non-empty line after the keyword line becomes an unchecked item, except `# headers`
        /// and `// comments`.
        public static func normalizedListNote(_ st: TextState) -> TextState {
            let count = Lines.ranges(st.ns).count
            guard count > 1 else { return st }
            return Lines.transform(st, lines: 1...(count - 1)) { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("#") || t.hasPrefix("//") || ListLine.parse(line) != nil { return line }
                return toggled(line)
            }
        }

        /// Clicking a checkbox: toggles line `index`; a newly checked item is then kept, moved to the bottom of its
        /// list block, or deleted per `behavior`.
        public static func check(_ st: TextState, line index: Int, behavior: CheckedItemBehavior) -> TextState {
            var lines = st.text.components(separatedBy: "\n")
            guard lines.indices.contains(index) else { return st }
            let toggledLine = toggled(lines[index])
            let becameChecked = ListLine.parse(toggledLine)?.isChecked == true
            lines[index] = toggledLine
            if becameChecked {
                switch behavior {
                case .keep: break
                case .delete: lines.remove(at: index)
                case .moveToBottom:
                    var end = index
                    while end + 1 < lines.count, ListLine.parse(lines[end + 1]) != nil { end += 1 }
                    let moved = lines.remove(at: index)
                    lines.insert(moved, at: end)
                }
            }
            let text = lines.joined(separator: "\n")
            let caret = min(st.selection.location, (text as NSString).length)
            return TextState(text, NSRange(location: caret, length: 0))
        }
    }

    /// Smallest single replacement turning `old` into `new` (common prefix/suffix trimmed).
    public static func minimalChange(from old: String, to new: String) -> (range: NSRange, replacement: String) {
        let a = old as NSString, b = new as NSString
        var prefix = 0
        let maxPrefix = min(a.length, b.length)
        while prefix < maxPrefix, a.character(at: prefix) == b.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < min(a.length, b.length) - prefix,
              a.character(at: a.length - 1 - suffix) == b.character(at: b.length - 1 - suffix) { suffix += 1 }
        return (NSRange(location: prefix, length: a.length - prefix - suffix),
                b.substring(with: NSRange(location: prefix, length: b.length - prefix - suffix)))
    }
}

// MARK: - Copy filters

extension EditorLogic {
    public enum Copy {
        public struct Options: Equatable {
            public var skipKeyword: Bool, uncheck: Bool, skipMarkers: Bool
            public init(skipKeyword: Bool, uncheck: Bool, skipMarkers: Bool) {
                self.skipKeyword = skipKeyword; self.uncheck = uncheck; self.skipMarkers = skipMarkers
            }
            public static var current: Options {
                Options(skipKeyword: Defaults[.skipKeywordWhenCopying], uncheck: Defaults[.copyListItemsUnchecked],
                        skipMarkers: Defaults[.skipListMarkersWhenCopying])
            }
        }

        /// Applies copy settings; `notices` lists the toast messages for what changed.
        /// `wholeNote` decides whether the first line can be a keyword line.
        public static func filter(_ text: String, wholeNote: Bool, options: Options) -> (text: String, notices: [String]) {
            var lines = text.components(separatedBy: "\n")
            var notices: [String] = []
            if wholeNote, options.skipKeyword, let first = lines.first, NoteMode.detect(firstLine: first).mode != .plain {
                lines.removeFirst()
                notices.append("Removed keyword from copied text.")
            }
            var unchecked = false, stripped = false
            lines = lines.map { line in
                guard var item = ListLine.parse(line) else { return line }
                if options.skipMarkers { stripped = true; return item.indent + item.content }
                if options.uncheck, item.isChecked { item.kind = .checkbox(checked: false); unchecked = true; return item.text }
                return line
            }
            if unchecked { notices.append("Copied list items as unchecked.") }
            if stripped { notices.append("Removed hidden list markers from copied text.") }
            return (lines.joined(separator: "\n"), notices)
        }
    }
}

// MARK: - Inline results

extension EditorLogic {
    /// Placement of math results, which sit right after the end of their line (not in a column).
    public enum Annotations {
        /// The text drawn after a line: a space then the result after a trailing "=" (" 96.00"), or " = 96.00"
        /// when the line has no trailing "=". No extra space when the line already ends in one.
        public static func display(_ result: String, after line: String) -> String {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let space = line.last?.isWhitespace == true ? "" : " "
            return trimmed.hasSuffix("=") ? space + result : space + "= " + result
        }

        /// Where a result of `width` goes: right after `lineEnd` (left-to-right) or before it (right-to-left)
        /// when it fits between `textStart` and `textEnd`; otherwise it wraps to a new row starting at the
        /// text edge, like a long expression's wrapped line.
        public static func place(lineEnd: CGFloat, width: CGFloat, textStart: CGFloat, textEnd: CGFloat,
                                 rightToLeft: Bool = false) -> (x: CGFloat, wraps: Bool) {
            if rightToLeft {
                return lineEnd - width >= textStart ? (lineEnd - width, false) : (max(textStart, textEnd - width), true)
            }
            return lineEnd + width <= textEnd ? (lineEnd, false) : (textStart, true)
        }
    }
}

// MARK: - Drawing geometry

extension EditorLogic {
    /// The caret inside the line rect AppKit hands to `drawInsertionPoint` (flipped): 2 pt wide, cap height
    /// + 7.8 pt tall, its foot on the bottom of the line less the font's leading.
    public static func caretRect(lineRect: CGRect, capHeight: CGFloat, leading: CGFloat) -> CGRect {
        let height = capHeight + 7.8
        return CGRect(x: lineRect.minX, y: lineRect.maxY - leading - height, width: 2, height: height)
    }

    /// The `backgroundFade` fill behind a fenced code block: its line fragments grown 4 pt sideways and 2 pt
    /// up and down (3 pt corners).
    public static func codeBlockRect(lines: CGRect) -> CGRect { lines.insetBy(dx: -4, dy: -2) }

    /// The fill behind an inline `code` span: its glyph box 2 pt wider each side, 0.8 pt shorter top and
    /// bottom, nudged 3 pt down (flipped) so it sits on the baseline (3 pt corners).
    public static func inlineCodeRect(glyphs: CGRect) -> CGRect {
        glyphs.insetBy(dx: -2, dy: 0.8).offsetBy(dx: 0, dy: 3)
    }

    /// The `::` list's action badge: its symbol and theme colour role.
    public static func actionBadge(_ action: String) -> (symbol: String, role: KeyPath<Theme, String>) {
        switch action.lowercased() {
        case "insert": ("arrow.down.to.line", \.accent3Main)
        case "replaceline": ("arrow.left.arrow.right", \.accent1Main)
        case "replaceall": ("doc.text.fill", \.accent2Main)
        case "openurl": ("link", \.accent2Main)
        default: ("questionmark.circle", \.typeLight)
        }
    }
}
