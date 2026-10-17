import Foundation

/// Modal editing state machine (Normal / Insert / Visual / Visual Line). It works on plain strings: the editor
/// feeds keys plus the current text and selection, and applies the returned text/selection.
///
/// Keys are single characters, or `<Esc>`, `<CR>`, `<BS>`, `<C-r>`.
public final class VimEngine {
    public enum Mode: Equatable { case normal, insert, visual, visualLine }

    public struct Output: Equatable {
        /// New text, nil when unchanged.
        public var text: String?
        public var selection: NSRange
        public var handled = true
        public var undo = false
        public var redo = false
    }

    public private(set) var mode: Mode = .normal
    public private(set) var cursor = 0
    private var anchor = 0
    private var count = ""
    private var pendingOperator: Character?
    private var operatorCount = 1
    private var pendingG = false
    private var search: String?
    private var lastSearch = ""
    private var register = ""
    private var registerLinewise = false
    private var desiredColumn: Int?

    public init() {}

    /// Short status for the mode label ("NORMAL", "VISUAL LINE", "/foo", "2d"…).
    public var status: String {
        if let search { return "/" + search }
        let base: String
        switch mode {
        case .normal: base = "NORMAL"
        case .insert: base = "INSERT"
        case .visual: base = "VISUAL"
        case .visualLine: base = "VISUAL LINE"
        }
        let pending = count + (pendingOperator.map(String.init) ?? "") + (pendingG ? "g" : "")
        return pending.isEmpty ? base : base + "  " + pending
    }

    public func reset() {
        mode = .normal
        count = ""; pendingOperator = nil; pendingG = false; search = nil; desiredColumn = nil
    }

    /// Syncs with a selection changed outside the engine (mouse, find bar).
    public func selectionChanged(_ sel: NSRange, text: String) {
        switch mode {
        case .insert: cursor = sel.location
        case .normal:
            if sel.length > 0 { mode = .visual; anchor = sel.location; cursor = max(sel.location, NSMaxRange(sel) - 1) }
            else { cursor = Motions.clampNormal(text as NSString, sel.location) }
        case .visual, .visualLine:
            if sel.length == 0 { mode = .normal; cursor = Motions.clampNormal(text as NSString, sel.location) }
        }
    }

    // MARK: Input

    public func handle(_ key: String, text: String, selection: NSRange) -> Output {
        let s = text as NSString
        if mode == .insert {
            guard key == "<Esc>" else { return Output(text: nil, selection: selection, handled: false) }
            mode = .normal
            let line = EditorLogic.Lines.range(s, at: selection.location)
            cursor = Motions.clampNormal(s, max(line.location, selection.location - 1))
            return out(s)
        }
        if mode == .normal, selection.length == 0 { cursor = Motions.clampNormal(s, selection.location) }

        if search != nil { return handleSearch(key, s) }
        if key == "<Esc>" { reset(); return out(s) }
        if key == "<C-r>" { var o = out(s); o.redo = true; return o }
        guard key.count == 1, let c = key.first else { return out(s) }

        if c.isNumber, !(c == "0" && count.isEmpty) { count.append(c); return out(s) }
        let n = Int(count) ?? 1
        let hadCount = !count.isEmpty
        count = ""

        if pendingG {
            pendingG = false
            if c == "g" { return motion(.line(hadCount ? n - 1 : 0), n: 1, s) }
            return out(s)
        }

        if mode == .visual || mode == .visualLine { return handleVisual(c, n: n, hadCount: hadCount, s) }
        return handleNormal(c, n: n, hadCount: hadCount, s)
    }

    private func handleNormal(_ c: Character, n: Int, hadCount: Bool, _ s: NSString) -> Output {
        if let op = pendingOperator {
            // Doubled operator: dd / yy / cc on `n` lines.
            if c == op { pendingOperator = nil; return linewise(op, lines: n * operatorCount, s) }
        }
        if let m = motionFor(c, n: n, hadCount: hadCount, s) {
            if c == "g" && m == .none { pendingG = true; if hadCount { count = String(n) }; return out(s) }
            return motion(m, n: n, s)
        }
        if pendingOperator != nil { pendingOperator = nil; return out(s) }
        let line = EditorLogic.Lines.range(s, at: cursor)
        switch c {
        case "d", "y", "c": pendingOperator = c; operatorCount = n; return out(s)
        case "i": return enterInsert(cursor, s)
        case "a": return enterInsert(min(cursor + (line.length > 0 ? 1 : 0), NSMaxRange(line)), s)
        case "I": return enterInsert(Motions.firstNonBlank(s, cursor), s)
        case "A": return enterInsert(NSMaxRange(line), s)
        case "o", "O":
            let indent = String(s.substring(with: line).prefix { $0 == " " || $0 == "\t" })
            let at = c == "o" ? NSMaxRange(line) : line.location
            let insert = c == "o" ? "\n" + indent : indent + "\n"
            let caret = c == "o" ? at + (insert as NSString).length : at + (indent as NSString).length
            mode = .insert; cursor = caret
            return Output(text: s.replacingCharacters(in: NSRange(location: at, length: 0), with: insert),
                          selection: NSRange(location: caret, length: 0))
        case "x":
            guard line.length > 0 else { return out(s) }
            let r = NSRange(location: cursor, length: min(n, NSMaxRange(line) - cursor))
            return delete(r, linewise: false, s)
        case "D", "C":
            let r = NSRange(location: cursor, length: NSMaxRange(line) - cursor)
            var o = delete(r, linewise: false, s)
            if c == "C" { mode = .insert; o.selection = NSRange(location: cursor, length: 0) }
            return o
        case "p", "P": return put(after: c == "p", n: n, s)
        case "u": var o = out(s); o.undo = true; return o
        case "v", "V":
            mode = c == "v" ? .visual : .visualLine; anchor = cursor
            return out(s)
        case "/": search = ""; return out(s)
        case "n", "N": return find(forward: c == "n", s)
        default: return out(s)
        }
    }

    private func handleVisual(_ c: Character, n: Int, hadCount: Bool, _ s: NSString) -> Output {
        if let m = motionFor(c, n: n, hadCount: hadCount, s) {
            if c == "g" && m == .none { pendingG = true; return out(s) }
            return motion(m, n: n, s)
        }
        let sel = visualRange(s)
        switch c {
        case "v", "V":
            let target: Mode = c == "v" ? .visual : .visualLine
            mode = mode == target ? .normal : target
            return out(s)
        case "d", "x":
            let o = delete(sel, linewise: mode == .visualLine, s)
            mode = .normal; return o
        case "y":
            yank(sel, linewise: mode == .visualLine, s)
            cursor = Motions.clampNormal(s, sel.location); mode = .normal
            return out(s)
        case "c":
            let linewise = mode == .visualLine
            var r = sel
            if linewise { r = EditorLogic.Lines.block(s, EditorLogic.Lines.covered(s, sel)) }
            yank(r, linewise: linewise, s)
            mode = .insert; cursor = r.location
            return Output(text: s.replacingCharacters(in: r, with: ""), selection: NSRange(location: r.location, length: 0))
        default: return out(s)
        }
    }

    // MARK: Motions

    enum Motion: Equatable {
        case none
        case char(Int, inclusive: Bool)   // characterwise target
        case line(Int)                    // linewise target line index
        case vertical(Int)                // j/k by delta lines (linewise for operators)
    }

    private func motionFor(_ c: Character, n: Int, hadCount: Bool, _ s: NSString) -> Motion? {
        switch c {
        case "h": return .char(Motions.left(s, cursor, n), inclusive: false)
        case "l": return .char(Motions.right(s, cursor, n, allowEnd: pendingOperator != nil), inclusive: false)
        case "j": return .vertical(n)
        case "k": return .vertical(-n)
        case "w":
            var t = Motions.wordForward(s, cursor, n)
            if pendingOperator != nil {
                let line = EditorLogic.Lines.range(s, at: cursor)
                if t > NSMaxRange(line) { t = NSMaxRange(line) }
                if pendingOperator == "c", cursor < s.length, !Motions.isSpace(s.character(at: cursor)) {
                    return .char(Motions.wordEnd(s, cursor, n), inclusive: true)
                }
            }
            return .char(t, inclusive: false)
        case "b": return .char(Motions.wordBackward(s, cursor, n), inclusive: false)
        case "e": return .char(Motions.wordEnd(s, cursor, n), inclusive: true)
        case "0": return .char(EditorLogic.Lines.range(s, at: cursor).location, inclusive: false)
        case "^": return .char(Motions.firstNonBlank(s, cursor), inclusive: false)
        case "$":
            let lines = EditorLogic.Lines.ranges(s)
            let target = lines[min(lines.count - 1, EditorLogic.Lines.index(s, at: cursor) + n - 1)]
            return .char(max(target.location, NSMaxRange(target) - 1), inclusive: true)
        case "G":
            let last = EditorLogic.Lines.ranges(s).count - 1
            return .line(hadCount ? min(n - 1, last) : last)
        case "g": return Motion.none
        default: return nil
        }
    }

    private func motion(_ m: Motion, n: Int, _ s: NSString) -> Output {
        let lines = EditorLogic.Lines.ranges(s)
        let current = EditorLogic.Lines.index(s, at: cursor)
        if let op = pendingOperator {
            pendingOperator = nil
            switch m {
            case .none: return out(s)
            case .line(let target):
                return linewise(op, from: min(current, target), to: max(current, target), s)
            case .vertical(let delta):
                let target = min(max(current + delta * operatorCount, 0), lines.count - 1)
                return linewise(op, from: min(current, target), to: max(current, target), s)
            case .char(let target, let inclusive):
                let lo = min(cursor, target), hi = max(cursor, target) + (inclusive ? 1 : 0)
                let r = NSRange(location: lo, length: min(hi, s.length) - lo)
                if op == "y" { yank(r, linewise: false, s); cursor = Motions.clampNormal(s, lo); return out(s) }
                var o = delete(r, linewise: false, s)
                if op == "c" { mode = .insert; cursor = lo; o.selection = NSRange(location: lo, length: 0) }
                return o
            }
        }
        switch m {
        case .none: break
        case .char(let target, _):
            cursor = mode == .normal ? Motions.clampNormal(s, target) : min(target, max(0, s.length - 1))
            desiredColumn = nil
        case .line(let target):
            cursor = Motions.firstNonBlank(s, lines[target].location); desiredColumn = nil
        case .vertical(let delta):
            let column = desiredColumn ?? (cursor - lines[current].location)
            desiredColumn = column
            let target = lines[min(max(current + delta, 0), lines.count - 1)]
            cursor = Motions.clampNormal(s, target.location + min(column, target.length))
        }
        return out(s)
    }

    // MARK: Edits

    private func linewise(_ op: Character, lines count: Int, _ s: NSString) -> Output {
        let current = EditorLogic.Lines.index(s, at: cursor)
        let last = EditorLogic.Lines.ranges(s).count - 1
        return linewise(op, from: current, to: min(current + count - 1, last), s)
    }

    private func linewise(_ op: Character, from: Int, to: Int, _ s: NSString) -> Output {
        let block = EditorLogic.Lines.block(s, from...to)
        switch op {
        case "y":
            yank(block, linewise: true, s)
            return out(s)
        case "c":
            yank(block, linewise: true, s)
            let indent = String(s.substring(with: block).prefix { $0 == " " || $0 == "\t" })
            mode = .insert
            cursor = block.location + (indent as NSString).length
            return Output(text: s.replacingCharacters(in: block, with: indent), selection: NSRange(location: cursor, length: 0))
        default:
            return delete(block, linewise: true, s)
        }
    }

    /// Deletes `r` (yanking it). Linewise deletes also remove one adjacent newline.
    private func delete(_ r: NSRange, linewise: Bool, _ s: NSString) -> Output {
        var r = r
        if linewise {
            r = EditorLogic.Lines.block(s, EditorLogic.Lines.covered(s, r))
            yank(r, linewise: true, s)
            if NSMaxRange(r) < s.length { r.length += 1 } else if r.location > 0 { r.location -= 1; r.length += 1 }
        } else {
            yank(r, linewise: false, s)
        }
        let text = s.replacingCharacters(in: r, with: "") as NSString
        let target = min(r.location, text.length)
        cursor = linewise ? Motions.firstNonBlank(text, target) : Motions.clampNormal(text, target)
        return Output(text: text as String, selection: NSRange(location: cursor, length: 0))
    }

    private func yank(_ r: NSRange, linewise: Bool, _ s: NSString) {
        register = s.substring(with: r)
        registerLinewise = linewise
    }

    private func put(after: Bool, n: Int, _ s: NSString) -> Output {
        guard !register.isEmpty || registerLinewise else { return out(s) }
        let payload = Array(repeating: register, count: n).joined(separator: registerLinewise ? "\n" : "")
        let line = EditorLogic.Lines.range(s, at: cursor)
        if registerLinewise {
            let at = after ? NSMaxRange(line) : line.location
            let insert = after ? "\n" + payload : payload + "\n"
            let text = s.replacingCharacters(in: NSRange(location: at, length: 0), with: insert) as NSString
            cursor = Motions.firstNonBlank(text, after ? at + 1 : at)
            return Output(text: text as String, selection: NSRange(location: cursor, length: 0))
        }
        let at = after ? min(cursor + (line.length > 0 ? 1 : 0), NSMaxRange(line)) : cursor
        let text = s.replacingCharacters(in: NSRange(location: at, length: 0), with: payload) as NSString
        cursor = Motions.clampNormal(text, at + (payload as NSString).length - 1)
        return Output(text: text as String, selection: NSRange(location: cursor, length: 0))
    }

    private func enterInsert(_ at: Int, _ s: NSString) -> Output {
        mode = .insert; cursor = at
        return Output(text: nil, selection: NSRange(location: at, length: 0))
    }

    // MARK: Search

    private func handleSearch(_ key: String, _ s: NSString) -> Output {
        switch key {
        case "<Esc>": search = nil
        case "<BS>":
            if search?.isEmpty == true { search = nil } else { search?.removeLast() }
        case "<CR>":
            lastSearch = search ?? ""; search = nil
            return find(forward: true, s)
        default:
            if key.count == 1 { search?.append(key) }
        }
        return out(s)
    }

    private func find(forward: Bool, _ s: NSString) -> Output {
        guard !lastSearch.isEmpty, let hit = Motions.search(s, lastSearch, from: cursor, forward: forward) else { return out(s) }
        cursor = hit
        return out(s)
    }

    // MARK: Output

    private func visualRange(_ s: NSString) -> NSRange {
        let lo = min(anchor, cursor), hi = max(anchor, cursor)
        if mode == .visualLine {
            return EditorLogic.Lines.block(s, EditorLogic.Lines.index(s, at: lo)...EditorLogic.Lines.index(s, at: hi))
        }
        return NSRange(location: lo, length: min(hi + 1, s.length) - lo)
    }

    private func out(_ s: NSString) -> Output {
        switch mode {
        case .visual, .visualLine: return Output(text: nil, selection: visualRange(s))
        default: return Output(text: nil, selection: NSRange(location: min(cursor, s.length), length: 0))
        }
    }

    // MARK: - Motion math

    public enum Motions {
        static func isSpace(_ c: unichar) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }
        static func isWord(_ c: unichar) -> Bool {
            guard let u = UnicodeScalar(c) else { return true }
            return CharacterSet.alphanumerics.contains(u) || c == 95
        }
        /// 0 = space, 1 = word, 2 = punctuation.
        static func kind(_ c: unichar) -> Int { isSpace(c) ? 0 : (isWord(c) ? 1 : 2) }

        /// Normal-mode caret: never on the newline of a non-empty line.
        public static func clampNormal(_ s: NSString, _ p: Int) -> Int {
            let p = min(max(p, 0), s.length)
            let line = EditorLogic.Lines.range(s, at: p)
            return line.length == 0 ? line.location : min(p, NSMaxRange(line) - 1)
        }

        public static func left(_ s: NSString, _ p: Int, _ n: Int) -> Int {
            max(EditorLogic.Lines.range(s, at: p).location, p - n)
        }

        public static func right(_ s: NSString, _ p: Int, _ n: Int, allowEnd: Bool = false) -> Int {
            let line = EditorLogic.Lines.range(s, at: p)
            return min(NSMaxRange(line) - (allowEnd || line.length == 0 ? 0 : 1), p + n)
        }

        public static func firstNonBlank(_ s: NSString, _ p: Int) -> Int {
            let line = EditorLogic.Lines.range(s, at: p)
            var i = line.location
            while i < NSMaxRange(line), s.character(at: i) == 32 || s.character(at: i) == 9 { i += 1 }
            return i
        }

        public static func wordForward(_ s: NSString, _ p: Int, _ n: Int) -> Int {
            var i = p
            for _ in 0..<n {
                guard i < s.length else { break }
                let k = kind(s.character(at: i))
                if k != 0 { while i < s.length, kind(s.character(at: i)) == k { i += 1 } }
                while i < s.length, isSpace(s.character(at: i)) {
                    // An empty line is a word of its own.
                    if s.character(at: i) == 10, i + 1 < s.length, s.character(at: i + 1) == 10 { i += 1; break }
                    i += 1
                }
            }
            return min(i, s.length)
        }

        public static func wordBackward(_ s: NSString, _ p: Int, _ n: Int) -> Int {
            var i = p
            for _ in 0..<n {
                guard i > 0 else { break }
                i -= 1
                while i > 0, isSpace(s.character(at: i)) { i -= 1 }
                let k = kind(s.character(at: i))
                while i > 0, kind(s.character(at: i - 1)) == k, k != 0 { i -= 1 }
            }
            return i
        }

        public static func wordEnd(_ s: NSString, _ p: Int, _ n: Int) -> Int {
            var i = p
            for _ in 0..<n {
                guard i + 1 < s.length else { break }
                i += 1
                while i < s.length - 1, isSpace(s.character(at: i)) { i += 1 }
                let k = kind(s.character(at: i))
                while i + 1 < s.length, kind(s.character(at: i + 1)) == k, k != 0 { i += 1 }
            }
            return i
        }

        /// Next occurrence of `needle` after (or before) `p`, wrapping around.
        public static func search(_ s: NSString, _ needle: String, from p: Int, forward: Bool) -> Int? {
            let opts: NSString.CompareOptions = [.caseInsensitive]
            if forward {
                let start = min(p + 1, s.length)
                let r = s.range(of: needle, options: opts, range: NSRange(location: start, length: s.length - start))
                if r.location != NSNotFound { return r.location }
                let w = s.range(of: needle, options: opts, range: NSRange(location: 0, length: s.length))
                return w.location == NSNotFound ? nil : w.location
            }
            let r = s.range(of: needle, options: opts.union(.backwards), range: NSRange(location: 0, length: max(0, p)))
            if r.location != NSNotFound { return r.location }
            let w = s.range(of: needle, options: opts.union(.backwards), range: NSRange(location: 0, length: s.length))
            return w.location == NSNotFound ? nil : w.location
        }
    }
}
