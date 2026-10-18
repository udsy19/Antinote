import Foundation
import SuperNotesCore

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

    /// The first marker of a new list in `style`.
    public static func kind(_ style: ListStyle) -> Kind {
        switch style {
        case .checkbox: .checkbox(checked: false)
        case .bullet: .bullet("-")
        case .numbered: .numbered(1)
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
        /// Settings → Editor → Automatic lists and Keywords → List: which markers make list items outside list
        /// notes, and what plain lines in a list note become.
        public struct Options: Equatable {
            public var defaultStyle: ListStyle
            public var checkboxes: Bool, bullets: Bool, numbered: Bool
            public init(defaultStyle: ListStyle = .checkbox, checkboxes: Bool = true, bullets: Bool = true, numbered: Bool = true) {
                self.defaultStyle = defaultStyle; self.checkboxes = checkboxes; self.bullets = bullets; self.numbered = numbered
            }
            public static var current: Options {
                Options(defaultStyle: Defaults[.defaultListStyle], checkboxes: Defaults[.inlineCheckboxes],
                        bullets: Defaults[.inlineBullets], numbered: Defaults[.inlineNumbered])
            }
            /// Every marker counts (list notes always have their markers).
            public var allMarkers: Options { Options(defaultStyle: defaultStyle) }

            public func allows(_ kind: ListLine.Kind) -> Bool {
                switch kind {
                case .checkbox: checkboxes
                case .bullet: bullets
                case .numbered: numbered
                }
            }

            /// The list item on `line`, when its marker counts.
            public func item(_ line: String) -> ListLine? {
                ListLine.parse(line).flatMap { allows($0.kind) ? $0 : nil }
            }
        }

        /// "Toggle Checklist Item": toggles a checkbox; turns any other line into an unchecked item.
        public static func toggled(_ line: String) -> String {
            if var l = ListLine.parse(line) {
                if case .checkbox(let checked) = l.kind { l.kind = .checkbox(checked: !checked) } else { l.kind = .checkbox(checked: false) }
                return l.text
            }
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            return indent + "[ ] " + line.dropFirst(indent.count)
        }

        /// ⌘⇧M: none → the default list style; then checkbox → bullet → numbered → checkbox.
        public static func cycled(_ line: String, start: ListStyle = .checkbox) -> String {
            guard var l = ListLine.parse(line) else { return started(line, style: start) }
            switch l.kind {
            case .checkbox: l.kind = .bullet("-")
            case .bullet: l.kind = .numbered(1)
            case .numbered: l.kind = .checkbox(checked: false)
            }
            return l.text
        }

        /// A plain line turned into a `style` list item (indentation kept).
        public static func started(_ line: String, style: ListStyle) -> String {
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            return indent + ListLine.marker(ListLine.kind(style)) + line.dropFirst(indent.count)
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

        public static func cycle(_ st: TextState, start: ListStyle = .checkbox) -> TextState {
            renumbered(Lines.transform(st, lines: Lines.covered(st.ns, st.selection)) { cycled($0, start: start) })
        }

        public static func indent(_ st: TextState, outdent: Bool) -> TextState {
            renumbered(Lines.transform(st, lines: Lines.covered(st.ns, st.selection), outdent ? outdented : indented))
        }

        /// Return inside a list item: split it into a new item (unchecked / same bullet / next number), or — on an
        /// empty item — outdent it, or remove the marker at the top level. Nil when the caret line is not an item.
        public static func continued(_ st: TextState, options: Options = Options()) -> TextState? {
            guard st.selection.length == 0 else { return nil }
            let s = st.ns, lineRange = Lines.range(s, at: st.selection.location)
            guard let item = options.item(s.substring(with: lineRange)) else { return nil }
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

        /// List notes: every non-empty line after the keyword line becomes an item in the default list style
        /// (`style`), except `# headers` and `// comments`.
        public static func normalizedListNote(_ st: TextState, style: ListStyle = .checkbox) -> TextState {
            let count = Lines.ranges(st.ns).count
            guard count > 1 else { return st }
            let normalized = Lines.transform(st, lines: 1...(count - 1)) { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("#") || t.hasPrefix("//") || ListLine.parse(line) != nil { return line }
                return started(line, style: style)
            }
            return style == .numbered && normalized.text != st.text ? renumbered(normalized) : normalized
        }

        /// A line whose text ends in one of `triggers` ("milk /x"), checked off with the trigger removed — always
        /// as a checkbox. The line must be a list item (`item`), or any text line of a list note. Nil otherwise.
        public static func checkedByTrigger(_ line: String, triggers: [String], item: ListLine?, inListNote: Bool) -> String? {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("//") else { return nil }
            let indent = item?.indent ?? String(line.prefix { $0 == " " || $0 == "\t" })
            guard item != nil || inListNote else { return nil }
            let content = item?.content ?? String(line.dropFirst(indent.count))
            for trigger in triggers where !trigger.isEmpty {
                guard content.lowercased().hasSuffix(trigger.lowercased()) else { continue }
                let text = String(content.dropLast(trigger.count)).trimmingCharacters(in: .whitespaces)
                return indent + ListLine.marker(.checkbox(checked: true)) + text
            }
            return nil
        }

        /// Typing a check trigger at the end of the caret's line checks the item off (then keeps, moves or deletes it
        /// per `behavior`). Nil when the caret line doesn't end in a trigger.
        public static func checkOffByTrigger(_ st: TextState, triggers: [String], options: Options, inListNote: Bool,
                                             behavior: CheckedItemBehavior) -> TextState? {
            let s = st.ns, lineRange = Lines.range(s, at: st.selection.location)
            let index = Lines.index(s, at: lineRange.location)
            guard st.selection.length == 0, st.selection.location == NSMaxRange(lineRange), !(inListNote && index == 0) else {
                return nil
            }
            let line = s.substring(with: lineRange)
            guard let checked = checkedByTrigger(line, triggers: triggers, item: options.item(line), inListNote: inListNote)
            else { return nil }
            let caretOnLine = TextState(s.replacingCharacters(in: lineRange, with: checked),
                                        NSRange(location: lineRange.location + (checked as NSString).length, length: 0))
            return place(caretOnLine, checkedLine: index, behavior: behavior)
        }

        /// Clicking a checkbox: toggles line `index`; a newly checked item is then kept, moved to the bottom of its
        /// list block, or deleted per `behavior`.
        public static func check(_ st: TextState, line index: Int, behavior: CheckedItemBehavior) -> TextState {
            var lines = st.text.components(separatedBy: "\n")
            guard lines.indices.contains(index) else { return st }
            lines[index] = toggled(lines[index])
            let caret = min(st.selection.location, (lines.joined(separator: "\n") as NSString).length)
            return place(TextState(lines.joined(separator: "\n"), NSRange(location: caret, length: 0)), checkedLine: index,
                         behavior: behavior)
        }

        /// Keeps, moves to the bottom of its list block, or deletes line `index` when it is a checked item.
        static func place(_ st: TextState, checkedLine index: Int, behavior: CheckedItemBehavior) -> TextState {
            var lines = st.text.components(separatedBy: "\n")
            guard lines.indices.contains(index), behavior != .keep else { return st }
            let becameChecked = ListLine.parse(lines[index])?.isChecked == true
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
    /// + 7.8 pt tall, its foot on the bottom of the line less the font's leading, raised by `nudge` points (the
    /// caret height offset setting; negative lowers it).
    public static func caretRect(lineRect: CGRect, capHeight: CGFloat, leading: CGFloat, nudge: CGFloat = 0) -> CGRect {
        let height = capHeight + 7.8
        return CGRect(x: lineRect.minX, y: lineRect.maxY - leading - height - nudge, width: 2, height: height)
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

// MARK: - "/" command list

extension EditorLogic {
    /// The inline "/" list: typing "/" at the start of a line (or after a space) lists the palette's commands
    /// under the caret; letters after it filter them.
    public enum Slash {
        /// The "/query" just before `caret` on the caret's line: a "/" at the start of the line's text (after any
        /// indentation and list marker) or after a space, then letters and digits only. With `emptyLineOnly` the "/"
        /// must be the only thing on its line (math and code notes, where "/" divides or starts a comment).
        public static func token(_ st: TextState, emptyLineOnly: Bool = false) -> (range: NSRange, query: String)? {
            guard st.selection.length == 0 else { return nil }
            let s = st.ns, line = Lines.range(s, at: st.selection.location)
            let before = s.substring(with: NSRange(location: line.location, length: st.selection.location - line.location))
            guard let slash = before.lastIndex(of: "/") else { return nil }
            let query = String(before[before.index(after: slash)...])
            guard query.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
            let lead = String(before[..<slash])
            let ok: Bool
            if emptyLineOnly {
                ok = lead.allSatisfy { $0 == " " || $0 == "\t" } && NSMaxRange(line) == st.selection.location
            } else {
                let afterMarker = ListLine.parse(lead).map { $0.content.isEmpty } ?? false
                ok = lead.isEmpty || lead.last == " " || lead.last == "\t" || afterMarker
            }
            guard ok else { return nil }
            let start = line.location + (lead as NSString).length
            return (NSRange(location: start, length: st.selection.location - start), query)
        }

        /// The quick pick for a digit typed right after a bare "/": 1…9 choose rows 0…8.
        public static func quickPick(_ key: String, query: String, rows: Int) -> Int? {
            guard query.isEmpty, key.count == 1, let n = Int(key), (1...9).contains(n), n <= rows else { return nil }
            return n - 1
        }

        /// Keyword commands first (in their order), then the rest, for a bare "/"; typed queries keep the ranking.
        public static func ordered(_ commands: [PaletteCommand], query: String) -> [PaletteCommand] {
            guard query.isEmpty else { return commands }
            return commands.filter { $0.keyword != nil } + commands.filter { $0.keyword == nil }
        }
    }
}

// MARK: - Inline command lists

extension EditorLogic {
    /// The `::` and "/" lists under the caret: which row is selected, which rows are scrolled into view, which row
    /// sits under the pointer, and where the list goes on screen. Rows are `rowHeight` tall below a `topPadding`
    /// strip, with the footer under the last visible row (y grows downwards).
    public struct CommandList: Equatable, Sendable {
        public static let rowHeight: Double = 28
        public static let topPadding: Double = 4
        public static let footerHeight: Double = 28
        /// Gap between the caret line and the list.
        public static let caretGap: Double = 6
        /// The list's left edge sits this far left of the caret.
        public static let caretLead: Double = 12

        public private(set) var count: Int
        /// Rows shown at once; more scroll.
        public let visible: Int
        public private(set) var selected = 0
        /// The first row shown.
        public private(set) var top = 0

        public init(count: Int = 0, visible: Int) {
            self.count = max(0, count)
            self.visible = max(1, visible)
        }

        /// Rows on screen (the empty state keeps room for two).
        public var shownRows: Int { min(count, visible) }
        public var canScroll: Bool { count > visible }
        /// The list's height: padding, the rows shown (at least two) and the footer.
        public var height: Double { Self.height(rows: shownRows) }
        public static func height(rows: Int) -> Double { topPadding + Double(max(rows, 2)) * rowHeight + footerHeight }

        /// New rows: the selection and scroll stay where they were when they still fit.
        public mutating func reset(count: Int) {
            self.count = max(0, count)
            select(min(selected, max(0, self.count - 1)))
        }

        /// Back to the first row (the list was closed).
        public mutating func rewind() { selected = 0; top = 0 }

        /// ↑/↓: moves the selection, wrapping, and scrolls it into view.
        public mutating func move(_ delta: Int) {
            guard count > 0 else { return }
            select(((selected + delta) % count + count) % count)
        }

        /// Selects `row` (clamped) and scrolls it into view.
        public mutating func select(_ row: Int) {
            guard count > 0 else { selected = 0; top = 0; return }
            selected = min(max(row, 0), count - 1)
            if selected < top { top = selected }
            if selected >= top + visible { top = selected - visible + 1 }
            top = min(max(top, 0), max(0, count - visible))
        }

        /// Scrolls by whole rows (positive shows later rows); the selection stays put.
        public mutating func scroll(by rows: Int) {
            top = min(max(top + rows, 0), max(0, count - visible))
        }

        /// The row under `y` (list coordinates, y down), if it is a shown row.
        public func row(atY y: Double) -> Int? {
            guard y >= Self.topPadding else { return nil }
            let shown = Int(((y - Self.topPadding) / Self.rowHeight).rounded(.down))
            guard shown < shownRows else { return nil }
            let row = top + shown
            return row < count ? row : nil
        }

        /// Top edge of `row` in list coordinates (rows above `top` are scrolled out, at negative offsets).
        public func y(of row: Int) -> Double { Self.topPadding + Double(row - top) * Self.rowHeight }

        /// The list's frame on screen (y up) for a caret line `anchor`: under the caret, its left edge a little
        /// left of it; above the caret when the caret is in the lower 40% of the note window or the list would
        /// run off the bottom of the screen (unless it would then run off the top). Kept inside `screen`.
        public static func frame(size: CGSize, anchor: CGRect, window: CGRect, screen: CGRect) -> CGRect {
            let belowY = anchor.minY - caretGap - size.height
            let aboveY = anchor.maxY + caretGap
            let fitsBelow = belowY >= screen.minY
            let fitsAbove = aboveY + size.height <= screen.maxY
            let lowInWindow = !window.isEmpty && anchor.minY < window.minY + window.height * 0.4
            let above = (lowInWindow || !fitsBelow) && (fitsAbove || !fitsBelow)
            var y = above ? aboveY : belowY
            y = min(max(y, screen.minY), screen.maxY - size.height)
            let x = min(max(anchor.minX - caretLead, screen.minX + 4), screen.maxX - size.width - 4)
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        }
    }
}

// MARK: - Parameter hint

extension EditorLogic {
    /// While the caret is inside the parentheses of a `::name(…)` on its line, a small popover shows the command's
    /// signature with the argument being typed in bold, and one line about that argument.
    public enum ParameterHint {
        /// A `::name(` whose parentheses hold the caret. Offsets are UTF-16, within the line.
        public struct Context: Equatable, Sendable {
            public var name: String
            /// Where "::" starts, where "(" is, and the closing ")" (nil until it's typed).
            public var start: Int
            public var open: Int
            public var close: Int?
            /// The argument the caret is in (0 = the first): the top-level commas before it.
            public var argument: Int
            /// Nothing but spaces between the parentheses.
            public var isEmpty: Bool
            /// What an argument list without its ")" still needs closed on Return: its quote, its parentheses.
            var openQuote: String
            var openDepth: Int
        }

        /// The invocation on `line` whose parentheses hold `caret` (a UTF-16 offset in the line): after its "(" and
        /// at or before its ")", or anywhere after the "(" while the ")" isn't typed. Arguments are read as the
        /// extension runner reads them (`InvocationArguments`). "::" right after a letter or digit ("std::max(")
        /// is code, not a command.
        public static func context(line: String, caret: Int) -> Context? {
            let ns = line as NSString
            guard caret >= 0, caret <= ns.length else { return nil }
            let caretIndex = String.Index(utf16Offset: caret, in: line)
            func offset(_ i: String.Index) -> Int { i.utf16Offset(in: line) }
            var from = line.startIndex
            while let colons = line.range(of: "::", range: from..<line.endIndex) {
                from = colons.upperBound
                if colons.lowerBound > line.startIndex {
                    let before = line[line.index(before: colons.lowerBound)]
                    if before.isLetter || before.isNumber || before == "_" || before == ":" { continue }
                }
                let name = line[colons.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
                guard !name.isEmpty else { continue }
                guard let open = line[name.endIndex...].firstIndex(where: { $0 != " " }), line[open] == "(" else {
                    from = name.endIndex
                    continue
                }
                let body = line.index(after: open)
                guard caretIndex >= body else { return nil }   // the caret is before this one's "("
                let scanned = InvocationArguments.scan(line[body...])
                if let close = scanned.close, caretIndex > close {
                    from = line.index(after: close)
                    continue
                }
                let before = InvocationArguments.scan(line[body..<caretIndex])
                let inside = line[body..<(scanned.close ?? line.endIndex)]
                var quote = ""
                if scanned.inQuote, let q = scanned.raw.last?.first(where: { $0 != " " && $0 != "\t" }) {
                    quote = q == "“" ? "”" : String(q)
                }
                return Context(name: String(name), start: offset(colons.lowerBound), open: offset(open),
                               close: scanned.close.map(offset), argument: before.raw.count - 1,
                               isEmpty: inside.allSatisfy { $0 == " " || $0 == "\t" }, openQuote: quote, openDepth: scanned.depth)
            }
            return nil
        }

        /// What Return runs for `context` on `line`: the invocation's range in the line and its text. An argument
        /// list without its ")" runs to the end of the line (less trailing spaces outside a quote) and gets the
        /// closing quote and parentheses it needs.
        public static func invocation(in line: String, _ context: Context) -> (range: NSRange, text: String) {
            let ns = line as NSString
            if let close = context.close {
                let range = NSRange(location: context.start, length: close + 1 - context.start)
                return (range, ns.substring(with: range))
            }
            var end = ns.length
            while context.openQuote.isEmpty, end > context.open + 1,
                  [" ", "\t"].contains(ns.substring(with: NSRange(location: end - 1, length: 1))) { end -= 1 }
            let range = NSRange(location: context.start, length: end - context.start)
            let closing = context.openQuote + String(repeating: ")", count: context.openDepth + 1)
            return (range, ns.substring(with: range) + closing)
        }

        /// The enabled command called `name`: a command name first, then an alias (ignoring case).
        public static func command(named name: String, in commands: [ExtensionCommandInfo]) -> ExtensionCommandInfo? {
            let key = name.lowercased()
            return commands.first { $0.name.lowercased() == key }
                ?? commands.first { $0.aliases.contains { $0.lowercased() == key } }
        }

        /// What the hint shows: the command, where the caret is in its arguments, and where it starts in the note.
        public struct Hint: Equatable {
            public var command: ExtensionCommandInfo
            public var context: Context
            /// The "::" in the whole text (UTF-16).
            public var location: Int
        }

        /// The hint for `st` (nil hides it): only with a bare caret inside a known command's parentheses, and never
        /// while a `::` or "/" list is open. `dismissed` is where Esc closed it: it stays closed while the caret is
        /// in that invocation, and is forgotten once the caret leaves it.
        public static func hint(_ st: TextState, commands: [ExtensionCommandInfo], listOpen: Bool, dismissed: inout Int?) -> Hint? {
            var found: Hint?
            if st.selection.length == 0 {
                let line = Lines.range(st.ns, at: st.selection.location)
                if let context = context(line: st.ns.substring(with: line), caret: st.selection.location - line.location),
                   let command = command(named: context.name, in: commands) {
                    found = Hint(command: command, context: context, location: line.location + context.start)
                }
            }
            if dismissed != found?.location { dismissed = nil }
            return listOpen || dismissed != nil ? nil : found
        }

        /// One run of the signature line.
        public struct Piece: Equatable, Sendable {
            public enum Role: Sendable { case name, required, optional, defaultValue }
            public var text: String
            public var role: Role
            /// The parameter the caret is in.
            public var current: Bool
            public init(_ text: String, _ role: Role, current: Bool = false) { self.text = text; self.role = role; self.current = current }
        }

        /// The parameter the caret's argument fills: surplus arguments join a last text parameter
        /// ("::pick(a, b, c)"); nil past the last of any other kind.
        public static func parameter(for argument: Int, of command: ExtensionCommandInfo) -> Int? {
            let count = command.parameters.count
            if argument < count { return argument }
            return command.parameters.last?.isText == true ? count - 1 : nil
        }

        /// "::today(" days " = 0" ", " format ")": optional parameters with their default, the current one marked.
        public static func signature(_ command: ExtensionCommandInfo, argument: Int) -> [Piece] {
            let current = parameter(for: argument, of: command)
            var pieces = [Piece("::\(command.name)(", .name)]
            for (i, p) in command.parameters.enumerated() {
                if i > 0 { pieces.append(Piece(", ", .name)) }
                pieces.append(Piece(p.name, p.isOptional ? .optional : .required, current: i == current))
                if p.isOptional, let value = p.defaultValue { pieces.append(Piece(" = \(value)", .defaultValue)) }
            }
            pieces.append(Piece(")", .name))
            return pieces
        }

        /// The line under the signature: the current parameter's name (drawn stronger) and what to write.
        public struct Detail: Equatable, Sendable {
            public var name: String?
            public var text: String
            public var line: String { name.map { "\($0) — \(text)" } ?? text }
        }

        public static func detail(_ command: ExtensionCommandInfo, argument: Int, isEmpty: Bool) -> Detail {
            let params = command.parameters
            if params.isEmpty { return Detail(text: "Press Return to run") }
            if isEmpty, params.allSatisfy(\.isOptional) {
                return Detail(text: "Press Return to use the defaults, or type to change them")
            }
            guard let index = parameter(for: argument, of: command) else {
                return Detail(text: "::\(command.name) takes \(params.count) argument\(params.count == 1 ? "" : "s"); remove the extra one")
            }
            let p = params[index]
            // Extensions that only give a signature: the command's help says what it does.
            var text = p.summary.isEmpty ? command.helpText : p.summary
            while text.hasSuffix(".") { text.removeLast() }
            var extras: [String] = []
            if let example = p.example { extras.append("e.g. \(example)") }
            text = ([text] + extras).filter { !$0.isEmpty }.joined(separator: ", ")
            if p.isOptional, let value = p.defaultValue { text += text.isEmpty ? "default \(value)" : " (default \(value))" }
            return text.isEmpty ? Detail(text: p.name) : Detail(name: p.name, text: text)
        }

        /// Gap between the caret and the hint.
        public static let caretGap: Double = 4

        /// The caret's box in the caret line `line` (y up), as the editor draws its caret (`caretRect`): what the
        /// hint sits just above or below.
        public static func caretBox(line: CGRect, capHeight: Double, leading: Double) -> CGRect {
            let caret = EditorLogic.caretRect(lineRect: CGRect(origin: .zero, size: line.size), capHeight: capHeight, leading: leading)
            return CGRect(x: line.minX, y: line.maxY - caret.maxY, width: line.width, height: caret.height)
        }

        /// The hint's frame on screen (y up): just above the caret (`caret`, its box), its text starting over the
        /// "::" at `startX` (`inset` is the hint's own left padding); below the caret when it would rise past the top
        /// of the note window or the screen. Sideways it stays inside the note window (6 pt in) when it fits, and
        /// always inside `screen`.
        public static func frame(size: CGSize, caret: CGRect, startX: Double, inset: Double, window: CGRect, screen: CGRect) -> CGRect {
            let above = caret.maxY + caretGap
            let top = window.isEmpty ? screen.maxY : min(window.maxY, screen.maxY)
            var y = above + size.height <= top ? above : caret.minY - caretGap - size.height
            y = min(max(y, screen.minY), screen.maxY - size.height)
            var x = startX - inset
            if !window.isEmpty, size.width <= window.width - 12 { x = min(max(x, window.minX + 6), window.maxX - size.width - 6) }
            x = min(max(x, screen.minX + 4), screen.maxX - size.width - 4)
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        }
    }
}

// MARK: - Find and replace

extension EditorLogic {
    /// The find shelf's matching: "Aa" (match case) and the match type popup.
    public enum Find {
        public enum MatchType: String, CaseIterable, Sendable {
            case contains, matchesWord, startsWith, endsWith, regex
            public var title: String {
                switch self {
                case .contains: "Contains"
                case .matchesWord: "Matches Word"
                case .startsWith: "Starts With"
                case .endsWith: "Ends With"
                case .regex: "Regex"
                }
            }
        }

        public struct Options: Equatable, Sendable {
            public var matchCase: Bool
            public var type: MatchType
            public init(matchCase: Bool = false, type: MatchType = .contains) { self.matchCase = matchCase; self.type = type }
        }

        /// The regular expression for `term` (nil for an empty term or an invalid regex).
        static func expression(_ term: String, _ options: Options) -> NSRegularExpression? {
            guard !term.isEmpty else { return nil }
            let word = #"[\p{L}\p{N}_]"#, literal = NSRegularExpression.escapedPattern(for: term)
            let pattern: String = switch options.type {
            case .contains: literal
            case .matchesWord: "(?<!\(word))\(literal)(?!\(word))"
            case .startsWith: "(?<!\(word))\(literal)"
            case .endsWith: "\(literal)(?!\(word))"
            case .regex: term
            }
            return try? NSRegularExpression(pattern: pattern, options: options.matchCase ? [] : [.caseInsensitive])
        }

        /// Every non-empty match of `term` in `text`, in order (UTF-16 ranges).
        public static func matches(of term: String, in text: String, options: Options) -> [NSRange] {
            guard let regex = expression(term, options) else { return [] }
            return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
                .map(\.range).filter { $0.length > 0 }
        }

        /// The match to show next: the first one starting at or after `location` (before it, backwards), wrapping.
        public static func next(from location: Int, in matches: [NSRange], backwards: Bool) -> Int? {
            guard !matches.isEmpty else { return nil }
            if backwards { return matches.lastIndex { $0.location < location } ?? matches.count - 1 }
            return matches.firstIndex { $0.location >= location } ?? 0
        }

        /// `text` with every match replaced (regex replacements may use `$1`), and how many there were.
        public static func replacingAll(_ term: String, with replacement: String, in text: String,
                                        options: Options) -> (text: String, count: Int) {
            guard let regex = expression(term, options) else { return (text, 0) }
            let full = NSRange(location: 0, length: (text as NSString).length)
            let count = regex.numberOfMatches(in: text, range: full)
            let template = options.type == .regex ? replacement : NSRegularExpression.escapedTemplate(for: replacement)
            return (regex.stringByReplacingMatches(in: text, range: full, withTemplate: template), count)
        }

        /// What replacing the single match `range` puts there (regex templates expanded).
        public static func replacement(for range: NSRange, in text: String, term: String, with replacement: String,
                                       options: Options) -> String {
            guard options.type == .regex, let regex = expression(term, options),
                  let m = regex.firstMatch(in: text, range: range), m.range == range else { return replacement }
            return regex.replacementString(for: m, in: text, offset: 0, template: replacement)
        }
    }
}
