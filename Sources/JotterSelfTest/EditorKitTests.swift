import AppKit
import JotterCore
import EditorKit

/// Feeds keys to a Vim engine, applying each output like the editor does.
private func vim(_ keys: [String], _ text: String, caret: Int = 0) -> (text: String, sel: NSRange, engine: VimEngine) {
    let engine = VimEngine()
    var text = text, sel = NSRange(location: caret, length: 0)
    for key in keys {
        let out = engine.handle(key, text: text, selection: sel)
        if !out.handled, key.count == 1 {   // insert mode: type the character
            text = (text as NSString).replacingCharacters(in: sel, with: key)
            sel = NSRange(location: sel.location + 1, length: 0)
            continue
        }
        if let t = out.text { text = t }
        sel = out.selection
    }
    return (text, sel, engine)
}

private func keys(_ s: String) -> [String] { s.map(String.init) }

/// Append cases with `SelfTest.cases.append(("name", { check(..., "msg") }))`.
func registerEditorKitTests() {
    SelfTest.cases.append(("EditorKit.listMarkers", {
        let box = ListLine.parse("[ ] milk")
        check(box?.kind == .checkbox(checked: false) && box?.markerLength == 4 && box?.content == "milk", "unchecked box")
        let done = ListLine.parse("\t[x] eggs")
        check(done?.indent == "\t" && done?.isChecked == true, "indented checked box")
        check(ListLine.parse("- a")?.kind == .bullet("-"), "bullet")
        check(ListLine.parse("12. twelve")?.kind == .numbered(12), "numbered")
        check(ListLine.parse("-5") == nil && ListLine.parse("1.5 kg") == nil, "math is not a list")
        check(ListLine.parse("[ ]")?.markerLength == 3, "bare checkbox")
    }))

    SelfTest.cases.append(("EditorKit.inlineResults", {
        typealias A = EditorLogic.Annotations
        check(A.display("96.00", after: "12 beds x 8 plants =") == " 96.00", "space after a trailing =")
        check(A.display("96.00", after: "12 x 8 = ") == "96.00", "no double space")
        check(A.display("400", after: "rent / 3") == " = 400", "adds = when the line has none")
        let fits = A.place(lineEnd: 200, width: 40, textStart: 44, textEnd: 293)
        check(fits.x == 200 && !fits.wraps, "result follows the line end")
        check(!A.place(lineEnd: 253, width: 40, textStart: 44, textEnd: 293).wraps, "exactly fits")
        let wraps = A.place(lineEnd: 260, width: 40, textStart: 44, textEnd: 293)
        check(wraps.x == 44 && wraps.wraps, "too long: wraps to the text start")
        let rtl = A.place(lineEnd: 100, width: 40, textStart: 44, textEnd: 293, rightToLeft: true)
        check(rtl.x == 60 && !rtl.wraps, "right-to-left: before the line end")
        check(A.place(lineEnd: 70, width: 40, textStart: 44, textEnd: 293, rightToLeft: true) == (253, true), "rtl wrap")
    }))

    SelfTest.cases.append(("EditorKit.listToggleCycle", {
        typealias L = EditorLogic.Lists
        check(L.toggled("buy") == "[ ] buy", "plain → checkbox")
        check(L.toggled("[ ] buy") == "[x] buy" && L.toggled("[x] buy") == "[ ] buy", "toggle")
        check(L.toggled("  - a") == "  [ ] a", "bullet → checkbox keeps indent")
        check(L.cycled("[ ] a") == "- a" && L.cycled("- a") == "1. a" && L.cycled("1. a") == "[ ] a", "cycle order")
        let cycled = L.cycle(TextState("a\nb", NSRange(location: 0, length: 3)))
        check(L.cycle(cycled).text == "- a\n- b", "cycle over a selection")
        check(L.cycle(L.cycle(cycled)).text == "1. a\n2. b", "numbered selection renumbers")
    }))

    SelfTest.cases.append(("EditorKit.listContinuation", {
        typealias L = EditorLogic.Lists
        let next = L.continued(TextState("[x] a", caret: 5))
        check(next == TextState("[x] a\n[ ] ", caret: 10), "new unchecked item")
        check(L.continued(TextState("1. a\n2. b", caret: 4))?.text == "1. a\n2. \n3. b", "numbers continue and renumber")
        check(L.continued(TextState("x\n- ", caret: 4)) == TextState("x\n", caret: 2), "empty item ends the list")
        check(L.continued(TextState("\t- ", caret: 3))?.text == "- ", "empty nested item outdents")
        check(L.continued(TextState("plain", caret: 5)) == nil, "not a list line")
        check(L.continued(TextState("[ ] a", caret: 1)) == nil, "caret inside the marker")
    }))

    SelfTest.cases.append(("EditorKit.listIndentRenumber", {
        typealias L = EditorLogic.Lists
        let ind = L.indent(TextState("a\nb", NSRange(location: 0, length: 3)), outdent: false)
        check(ind.text == "\ta\n\tb", "indent block")
        check(L.indent(TextState("\t- a", caret: 4), outdent: true) == TextState("- a", caret: 3), "outdent keeps caret on text")
        check(L.outdented("    x") == "x" && L.outdented("  x") == "x", "outdent spaces")
        check(L.renumber("3. a\n5. b\n\n1. c\n7. d") == "3. a\n4. b\n\n1. c\n2. d", "runs renumber, blank line resets")
        check(L.renumber("1. a\n\t1. x\n\t5. y\n9. b") == "1. a\n\t1. x\n\t2. y\n2. b", "nested levels count separately")
    }))

    SelfTest.cases.append(("EditorKit.checkedBehavior", {
        typealias L = EditorLogic.Lists
        let st = TextState("list\n[ ] a\n[ ] b\n[ ] c")
        check(L.check(st, line: 1, behavior: .keep).text == "list\n[x] a\n[ ] b\n[ ] c", "keep")
        check(L.check(st, line: 1, behavior: .moveToBottom).text == "list\n[ ] b\n[ ] c\n[x] a", "move to bottom")
        check(L.check(st, line: 1, behavior: .delete).text == "list\n[ ] b\n[ ] c", "delete")
        check(L.check(TextState("[x] a\n[ ] b"), line: 0, behavior: .delete).text == "[ ] a\n[ ] b", "unchecking never deletes")
        let n = L.normalizedListNote(TextState("todo\nmilk\n\n[x] eggs", caret: 9))
        check(n == TextState("todo\n[ ] milk\n\n[x] eggs", caret: 13), "list notes get markers; caret follows")
        let headed = L.normalizedListNote(TextState("list\n# Monday\nbeans\n// Drinks\nfizz"))
        check(headed.text == "list\n# Monday\n[ ] beans\n// Drinks\n[ ] fizz", "headers and comments stay unchecked")
    }))

    SelfTest.cases.append(("EditorKit.lineEditing", {
        typealias L = EditorLogic.Lines
        check(L.move(TextState("a\nb\nc", caret: 2), up: true) == TextState("b\na\nc", caret: 0), "move up")
        check(L.move(TextState("a\nb\nc", caret: 2), up: false) == TextState("a\nc\nb", caret: 4), "move down")
        check(L.move(TextState("a\nb", caret: 2), up: false) == nil, "bottom edge")
        check(L.duplicate(TextState("a\nb", caret: 0), up: false) == TextState("a\na\nb", caret: 2), "duplicate down")
        check(L.duplicate(TextState("a\nb", caret: 2), up: true) == TextState("a\nb\nb", caret: 2), "duplicate up")
        let struck = L.strikethrough(TextState("hello world", NSRange(location: 0, length: 5)))
        check(struck == TextState("~~hello~~ world", NSRange(location: 2, length: 5)), "wrap selection")
        check(L.strikethrough(struck!)?.text == "hello world", "unwrap selection")
        check(L.strikethrough(TextState("[ ] task", caret: 6))?.text == "[ ] ~~task~~", "line content after marker")
        check(L.covered("a\nb\nc" as NSString, NSRange(location: 0, length: 2)) == 0...0, "selection ending at newline")
    }))

    SelfTest.cases.append(("EditorKit.links", {
        typealias K = EditorLogic.Links
        let link = ShortLink(url: "https://github.com/a/b/pull/42", short: "github.com/…/42")
        let text = "see github.com/…/42 now"
        let located = K.locate([link], in: text)
        check(located.count == 1 && located[0].range.location == 4, "locate by short text")
        let r = located[0].range
        let before = K.adjust(located, edited: NSRange(location: 0, length: 0), replacement: "ab", text: "ab" + text)
        check(before.first?.range.location == 6, "edit before shifts")
        let after = K.adjust(located, edited: NSRange(location: 23, length: 0), replacement: "!", text: text + "!")
        check(after.first?.range == r, "edit after leaves it")
        let gone = K.adjust(located, edited: r, replacement: "", text: "see  now")
        check(gone.isEmpty, "deleting the link drops it")
        check(K.check(NSRange(location: r.location + 2, length: 0), against: located) == .inside, "typing inside blocked")
        check(K.check(NSRange(location: r.location, length: 0), against: located) == .allowed, "typing at the edge allowed")
        check(K.check(NSRange(location: 2, length: 4), against: located) == .partial, "partial delete blocked")
        check(K.check(NSRange(location: 2, length: 20), against: located) == .allowed, "whole link delete allowed")
        let expanded = [TrackedLink(link: ShortLink(url: "https://a.com/x", short: "a.com/x"), range: NSRange(location: 0, length: 15), expanded: true)]
        let grown = K.adjust(expanded, edited: NSRange(location: 15, length: 0), replacement: "y", text: "https://a.com/xy")
        check(grown.first?.link.url == "https://a.com/xy" && grown.first?.range.length == 16, "expanded link absorbs edits")
        check(K.collapsed("https://a.com/x!", links: expanded) == "a.com/x!", "stored text is collapsed")
        check(K.expanded(text, range: NSRange(location: 0, length: 23), links: located) == "see https://github.com/a/b/pull/42 now", "copy expands")
    }))

    SelfTest.cases.append(("EditorKit.linkDetection", {
        typealias K = EditorLogic.Links
        let s = "(see https://x.com/a). and https://en.wikipedia.org/wiki/Foo_(bar)"
        let urls = K.urls(in: s).map { (s as NSString).substring(with: $0) }
        check(urls == ["https://x.com/a", "https://en.wikipedia.org/wiki/Foo_(bar)"], "trailing punctuation trimmed: \(urls)")
        let shrunk = K.shrink("go https://example.com/a/b/c now") { _ in "example.com/…/c" }
        check(shrunk.text == "go example.com/…/c now", "shrink text")
        check(shrunk.links.first?.range == NSRange(location: 3, length: ("example.com/…/c" as NSString).length), "shrink range")
        check(K.url(endingAt: 22, in: "go https://example.com more") != nil, "typed URL before caret")
    }))

    SelfTest.cases.append(("EditorKit.copyFilter", {
        typealias C = EditorLogic.Copy
        let all = C.filter("list\n[x] a\n[ ] b", wholeNote: true, options: .init(skipKeyword: true, uncheck: true, skipMarkers: false))
        check(all.text == "[ ] a\n[ ] b" && all.notices.count == 2, "keyword dropped, items unchecked")
        let bare = C.filter("- a\n1. b\n[x] c", wholeNote: false, options: .init(skipKeyword: true, uncheck: false, skipMarkers: true))
        check(bare.text == "a\nb\nc", "markers dropped")
        check(C.filter("hello\nworld", wholeNote: true, options: .init(skipKeyword: true, uncheck: true, skipMarkers: true)).text
              == "hello\nworld", "plain first line kept")
        let change = EditorLogic.minimalChange(from: "abcdef", to: "abXYef")
        check(change.range == NSRange(location: 2, length: 2) && change.replacement == "XY", "minimal change")
    }))

    SelfTest.cases.append(("EditorKit.vimMotions", {
        typealias M = VimEngine.Motions
        let s = "foo bar.baz" as NSString
        check(M.wordForward(s, 0, 1) == 4 && M.wordForward(s, 4, 1) == 7 && M.wordForward(s, 7, 1) == 8, "w")
        check(M.wordForward(s, 0, 2) == 7, "2w")
        check(M.wordBackward("foo bar" as NSString, 6, 1) == 4 && M.wordBackward("foo bar" as NSString, 4, 1) == 0, "b")
        check(M.wordEnd("foo bar" as NSString, 0, 1) == 2 && M.wordEnd("foo bar" as NSString, 2, 1) == 6, "e")
        check(M.wordForward("ab\n\ncd" as NSString, 0, 1) == 3, "w stops at an empty line")
        check(M.clampNormal("ab\ncd" as NSString, 2) == 1, "normal caret not on newline")
        check(M.firstNonBlank("x\n   y" as NSString, 3) == 5, "^")
        check(M.search("one two one" as NSString, "one", from: 0, forward: true) == 8, "search forward")
        check(M.search("one two one" as NSString, "one", from: 8, forward: true) == 0, "search wraps")
    }))

    SelfTest.cases.append(("EditorKit.vimEditing", {
        let t = "hello world\nsecond line"
        check(vim(["w"], t).sel.location == 6, "w moves")
        check(vim(["$"], t).sel.location == 10 && vim(["G"], t).sel.location == 12 && vim(["G", "g", "g"], t).sel.location == 0, "$ G gg")
        check(vim(["3", "l"], t).sel.location == 3, "count")
        check(vim(["$", "j"], t).sel.location == 22, "j keeps column")
        check(vim(keys("dw"), t).text == "world\nsecond line", "dw")
        check(vim(keys("dd"), t).text == "second line", "dd")
        check(vim(keys("2dd"), t + "\nthird").text == "third", "2dd")
        check(vim(keys("yyp"), t).text == "hello world\nhello world\nsecond line", "yy p")
        check(vim(keys("yyjP"), t).text == "hello world\nhello world\nsecond line", "yy P above")
        check(vim(keys("x"), t).text == "ello world\nsecond line", "x")
        check(vim(keys("wD"), t).text == "hello \nsecond line", "D")
        let cw = vim(keys("cw") + keys("bye"), t)
        check(cw.text == "bye world\nsecond line" && cw.engine.mode == .insert, "cw then type")
        let o = vim(keys("o"), t)
        check(o.text == "hello world\n\nsecond line" && o.sel.location == 12 && o.engine.mode == .insert, "o")
        let esc = vim(keys("A") + ["<Esc>"], t)
        check(esc.engine.mode == .normal && esc.sel.location == 10, "A then Esc steps back")
        check(vim(keys("ved"), t).text == " world\nsecond line", "visual delete")
        check(vim(keys("jVd"), t).text == "hello world", "visual line delete")
        check(vim(keys("u"), t).text == t, "u leaves text to the undo manager")
        check(vim(["/", "s", "e", "c", "<CR>"], t).sel.location == 12, "/ search")
        check(vim(["/", "l", "<CR>", "n"], t).sel.location == 3, "n repeats")
        check(vim(keys("v") + ["<Esc>"], t).engine.mode == .normal, "Esc leaves visual")
    }))

    SelfTest.cases.append(("EditorKit.codeTokenizer", {
        check(CodeTokenizer.detect("def foo():\n    return None") == .python, "python")
        check(CodeTokenizer.detect("func x() -> Int {\n  let a = 1\n  return a\n}") == .swift, "swift")
        check(CodeTokenizer.detect("SELECT * FROM users WHERE id = 1") == .sql, "sql")
        check(CodeTokenizer.detect("{\"a\": 1}") == .json, "json")
        check(CodeLanguage(name: "ts") == .javascript, "alias")
        let code = "let s = \"hi\" // note\n42"
        let tokens = CodeTokenizer.tokens(code, language: .swift)
        let kinds = tokens.map(\.kind)
        check(kinds == [.keyword, .string, .comment, .number], "token kinds: \(kinds)")
        check(tokens[1].range == NSRange(location: 8, length: 4), "string range")
        let py = CodeTokenizer.tokens("x = '''a\nb''' # c", language: .python)
        check(py.map(\.kind) == [.string, .comment], "python triple quotes")
        check(CodeTokenizer.tokens("a1 = x2", language: .generic).isEmpty, "digits inside identifiers are not numbers")
    }))
    SelfTest.cases.append(("EditorKit.editorSmoke", {
        MainActor.assumeIsolated {
            let editor = JotterEditorFactory().makeEditor()
            editor.view.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
            editor.view.layoutSubtreeIfNeeded()
            var analyses = 0
            editor.onAnalysis = { _ in analyses += 1 }
            editor.load(Note(content: "todo\nmilk\n[x] eggs"))
            guard let tv = editor.view.subviews.compactMap({ $0 as? NSScrollView }).first?.documentView as? NSTextView else {
                return check(false, "text view embedded in a scroll view")
            }
            check(tv.string == "todo\n[ ] milk\n[x] eggs", "list note normalized on load: \(tv.string)")
            check(analyses > 0, "analysis published on load")
            tv.setSelectedRange(NSRange(location: 6, length: 0))
            check(tv.selectedRange().location == 9, "caret skips the hidden checkbox marker \(tv.selectedRange())")
            editor.perform(.moveLineDown)
            check(tv.string == "todo\n[x] eggs\n[ ] milk", "move line down")
            editor.perform(.toggleCheckbox)
            check(tv.string.hasSuffix("[x] milk"), "toggle current item")
            editor.perform(.cycleListStyle)
            check(tv.string == "todo\n[x] eggs\n- milk", "cycle style")
            let rep = editor.view.bitmapImageRepForCachingDisplay(in: editor.view.bounds)!
            editor.view.cacheDisplay(in: editor.view.bounds, to: rep)

            editor.load(Note(content: "see gh/…/1 x", links: [ShortLink(url: "https://github.com/1", short: "gh/…/1")]))
            tv.setSelectedRange(NSRange(location: 6, length: 0))
            tv.insertText("Z", replacementRange: tv.selectedRange())
            check(tv.string == "see gh/…/1 x", "typing inside a short link is blocked")
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            tv.insertText("I ", replacementRange: tv.selectedRange())
            check(tv.string == "I see gh/…/1 x", "typing before a short link works")
            editor.perform(.expandAllLinks)
            check(tv.string == "I see https://github.com/1 x", "expand all links: \(tv.string)")
            editor.perform(.expandAllLinks)
            check(!tv.string.contains("https://"), "links collapse again")

            editor.load(Note(content: "code swift\nlet a = \"x\" // c", isReadOnly: true))
            tv.insertText("Z", replacementRange: NSRange(location: 0, length: 0))
            check(!tv.string.contains("Z"), "read-only notes are not editable")
            editor.view.cacheDisplay(in: editor.view.bounds, to: rep)
        }
    }))
}
