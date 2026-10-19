import AppKit
import SuperNotesCore
import EditorKit
import NoteEngine

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

/// `::` commands for the parameter-hint cases: what the editor runs is recorded, and every run inserts "RAN".
@MainActor
private final class RecordingExtensions: ExtensionsServicing {
    let commands: [ExtensionCommandInfo]
    var runs: [(invocation: String, line: String)] = []
    init(_ commands: [ExtensionCommandInfo]) { self.commands = commands }
    func complete(_ prefix: String) -> [ExtensionCommandInfo] { commands.filter { $0.name.hasPrefix(prefix) } }
    func run(invocation: String, line: String, note: String, progress: @escaping (ExtensionProgress) -> Void,
             completion: @escaping (ExtensionEdit) -> Void) -> ExtensionRun {
        runs.append((invocation, line))
        completion(.insert("RAN"))
        return ExtensionRun()
    }
    func reload() {}
    func makeSettingsView() -> NSView { NSView() }
}

private func hintCommand(_ name: String, aliases: [String] = [], _ parameters: [ExtensionParameter], help: String = "") -> ExtensionCommandInfo {
    ExtensionCommandInfo(name: name, aliases: aliases, extensionName: "test", helpText: help, signature: "", action: "insert",
                         parameters: parameters)
}

private let hintCommands = [
    hintCommand("today", aliases: ["date"], [ExtensionParameter(name: "days", summary: "how many days from today", isOptional: true,
                                                                 defaultValue: "0", example: "3 or -1"),
                                              ExtensionParameter(name: "format", summary: "iso, us or a pattern", isOptional: true)]),
    hintCommand("loan", [ExtensionParameter(name: "principal", summary: "the amount borrowed"),
                         ExtensionParameter(name: "rate", summary: "yearly interest rate in percent", example: "6.5"),
                         ExtensionParameter(name: "years", summary: "how long it runs")]),
    hintCommand("pick", [ExtensionParameter(name: "items", summary: "choices", isText: true)]),
    hintCommand("coin", []),
]

/// `text` with "|" marking the caret.
private func caretState(_ text: String) -> TextState {
    let caret = (text as NSString).range(of: "|").location
    return TextState(text.replacingOccurrences(of: "|", with: ""), caret: caret)
}

/// Append cases with `SelfTest.cases.append(("name", { check(..., "msg") }))`.
func registerEditorKitTests() {
    SelfTest.cases.append(("EditorKit.autoCapitalize", {
        typealias C = EditorLogic.Capitalization
        func fixed(_ text: String, _ at: Int, skip: Set<Int> = [], protected: [NSRange] = []) -> String? {
            C.applied(TextState(text, caret: at + 1), separatorAt: at, skipLines: skip, protected: protected)?.text
        }
        check(C.isSeparator(" ") && C.isSeparator("\n") && C.isSeparator("\t") && !C.isSeparator(".") && !C.isSeparator(":"),
              "a space, newline or tab finishes a word; punctuation doesn't (URLs, 'www.')")
        check(fixed("hello ", 5) == "Hello ", "the first word of a note")
        check(fixed("Hello world ", 11) == nil, "mid-sentence words stay")
        check(fixed("one. two ", 8) == "one. Two ", "after a full stop and a space")
        check(fixed("really? yes ", 11) == "really? Yes ", "after a question mark")
        check(fixed("\"Quoted.\" next ", 14) == "\"Quoted.\" Next ", "closing quotes after the stop are fine")
        check(fixed("line one\nsecond ", 15) == "line one\nSecond ", "the start of a line")
        check(fixed("  indented ", 10) == "  Indented ", "after indentation")
        check(fixed("[ ] milk ", 8) == "[ ] Milk ", "after a checkbox")
        check(fixed("- apples ", 8) == "- Apples ", "after a bullet")
        check(fixed("1. first ", 8) == "1. First ", "after a number")
        check(fixed("## heading ", 10) == "## Heading ", "after heading marks")
        check(fixed("see example.com ", 15) == nil, "'com' after a dot with no space is no sentence")
        check(fixed("https://x ", 9) == nil && fixed("a/b/c ", 5) == nil && fixed("me@x ", 4) == nil, "paths, URLs and addresses")
        check(fixed("e.g. this ", 9) == nil && fixed("vs. that ", 8) == nil, "abbreviations don't end sentences")
        check(fixed("I am. fine ", 10) == "I am. Fine ", "'am.' does")
        check(fixed("x. yes ", 6) == nil && fixed("a. yes ", 6) == "a. Yes ", "a lone letter before the stop reads as a list marker, except a / i")
        check(fixed("Hello ", 5) == nil && fixed("iPhone ", 6) == nil, "already capitalised, or mixed case, stays")
        check(fixed("don't ", 5) == "Don't ", "apostrophes belong to the word")
        check(fixed("über ", 4) == "Über ", "non-ASCII letters")
        check(fixed("ß ", 1) == nil, "a letter whose capital is two letters is left alone")
        check(fixed("123 abc ", 7) == nil, "after a number mid-line: no sentence start")
        check(fixed("math\n1 + 1 ", 6) == nil, "math is never capitalised here (skipped by mode); the second line of plain text is not a sentence start after '+'")
        check(fixed("list\nmilk ", 9, skip: [0]) == "list\nMilk " && fixed("list ", 4, skip: [0]) == nil, "the keyword line is skipped")
        check(fixed("code here ", 9, protected: [NSRange(location: 0, length: 10)]) == nil, "protected ranges (code, links) stay")
        check(fixed("", 0) == nil && fixed(" ", 1) == nil, "nothing to do")
        check(C.applied(TextState("hello ", caret: 6), separatorAt: 5)?.selection == NSRange(location: 6, length: 0), "the caret stays put")
    }))

    SelfTest.cases.append(("EditorKit.commandListSelection", {
        var list = EditorLogic.CommandList(count: 12, visible: 9)
        check(list.selected == 0 && list.top == 0 && list.shownRows == 9 && list.canScroll, "starts at the top, 9 of 12 shown")
        list.move(-1)
        check(list.selected == 11 && list.top == 3, "↑ from the first row wraps to the last and scrolls it into view")
        list.move(1)
        check(list.selected == 0 && list.top == 0, "↓ from the last wraps to the first")
        list.select(9)
        check(list.top == 1, "selecting below the view scrolls just enough")
        list.reset(count: 3)
        check(list.selected == 2 && list.top == 0 && !list.canScroll, "fewer rows: selection clamped, no scrolling")
        list.rewind()
        check(list.selected == 0 && list.top == 0, "closing rewinds")
        var empty = EditorLogic.CommandList(count: 0, visible: 8)
        empty.move(1)
        check(empty.selected == 0 && empty.row(atY: 10) == nil, "an empty list has no rows to pick")
        check(empty.height == EditorLogic.CommandList.height(rows: 2), "the empty state keeps room for two rows")
    }))

    SelfTest.cases.append(("EditorKit.commandListPointer", {
        typealias L = EditorLogic.CommandList
        var list = L(count: 12, visible: 9)
        check(list.row(atY: L.topPadding - 1) == nil, "the top padding is no row")
        check(list.row(atY: L.topPadding) == 0 && list.row(atY: L.topPadding + L.rowHeight - 0.5) == 0, "first row's band")
        check(list.row(atY: L.topPadding + L.rowHeight * 3.5) == 3, "row under the pointer")
        check(list.row(atY: L.topPadding + L.rowHeight * 9) == nil, "the footer is no row")
        list.scroll(by: 2)
        check(list.top == 2 && list.selected == 0, "the wheel scrolls without moving the selection")
        check(list.row(atY: L.topPadding + 1) == 2, "after scrolling, the top band is the first row shown")
        check(list.y(of: 2) == L.topPadding && list.y(of: 0) < 0, "rows above the view sit above it")
        list.scroll(by: 50)
        check(list.top == 3, "scrolling stops at the last page")
        list.scroll(by: -50)
        check(list.top == 0, "and at the first")
        if let hovered = list.row(atY: L.topPadding + L.rowHeight * 4.2) { list.select(hovered) }
        check(list.selected == 4 && list.top == 0, "hovering selects the row without scrolling")
        let short = L(count: 3, visible: 9)
        check(short.row(atY: L.topPadding + L.rowHeight * 3.5) == nil, "below the last row of a short list")
        check(short.height == L.topPadding + 3 * L.rowHeight + L.footerHeight, "height fits the rows shown")
    }))

    SelfTest.cases.append(("EditorKit.commandListPlacement", {
        typealias L = EditorLogic.CommandList
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window = CGRect(x: 400, y: 300, width: 350, height: 400)
        let size = CGSize(width: 280, height: 200)
        let high = CGRect(x: 460, y: 640, width: 1, height: 18)   // near the window's top
        let below = L.frame(size: size, anchor: high, window: window, screen: screen)
        check(below.maxY == high.minY - L.caretGap && below.minX == high.minX - L.caretLead, "under the caret, a little left of it")
        let low = CGRect(x: 460, y: 340, width: 1, height: 18)    // in the window's lower 40%
        let above = L.frame(size: size, anchor: low, window: window, screen: screen)
        check(above.minY == low.maxY + L.caretGap, "low in the window: above the caret")
        let nearScreenBottom = CGRect(x: 460, y: 120, width: 1, height: 18)
        let flipped = L.frame(size: size, anchor: nearScreenBottom, window: CGRect(x: 400, y: 0, width: 350, height: 900), screen: screen)
        check(flipped.minY > nearScreenBottom.maxY, "would run off the screen's bottom: above")
        let tallScreen = CGRect(x: 0, y: 0, width: 1440, height: 260)
        let squeezed = L.frame(size: size, anchor: CGRect(x: 460, y: 150, width: 1, height: 18), window: .zero, screen: tallScreen)
        check(squeezed.minY >= tallScreen.minY && squeezed.maxY <= tallScreen.maxY, "never off the screen")
        let edge = L.frame(size: size, anchor: CGRect(x: 1430, y: 640, width: 1, height: 18), window: window, screen: screen)
        check(edge.maxX <= screen.maxX - 4, "kept inside the screen's right edge")
    }))

    SelfTest.cases.append(("EditorKit.parameterHintContext", {
        typealias H = EditorLogic.ParameterHint
        func context(_ marked: String) -> H.Context? {
            let st = caretState(marked)
            return H.context(line: st.text, caret: st.selection.location)
        }
        func argument(_ marked: String) -> Int? { context(marked)?.argument }
        check(argument("::today(|)") == 0 && argument("::today(3|)") == 0, "first argument")
        check(argument("::loan(300000, |)") == 1 && argument("::loan(1, 2,| 3)") == 2, "commas before the caret count")
        check(argument(#"::f("a, b", |)"#) == 1 && argument(#"::f("a, |b")"#) == 0, "commas inside quotes don't")
        check(argument(#"::f("a \", b", |)"#) == 1, "an escaped quote doesn't close the quote")
        check(argument("::f((1, 2), |)") == 1 && argument("::f((1,| 2))") == 0, "commas inside nested parentheses don't")
        check(argument("::f(don't, |)") == 1, "an apostrophe in a word opens no quote")
        check(argument(#"::f(a\, |)"#) == 1, "a backslash outside quotes doesn't hide a comma, as the runner reads it")
        check(context("::today|()") == nil && context("::to|day()") == nil, "not before the (")
        check(context("::today()|") == nil && context("::today(3)| more") == nil, "not after the )")
        check(context("::today(3|)")?.close == 9 && context("::today(3|")?.close == nil, "the ) when it is there")
        check(argument("note ::today(3, |") == 1, "no ) yet: the rest of the line")
        check(argument("::a(1) and ::b(x, |)") == 1 && context("::a(1) and ::b(x, |)")?.name == "b", "the second invocation on a line")
        check(context("::a(1|) and ::b(x)")?.name == "a", "the first one")
        check(context("std::max(a, |b)") == nil && context("x ::max(a, |b)")?.name == "max", "code like std::max( is not a command")
        check(context("::today (|)")?.name == "today", "a space before ( is allowed, as the runner allows")
        check(context("::today(|)")?.isEmpty == true && context("::today( | )")?.isEmpty == true && context("::today(3|)")?.isEmpty == false,
              "empty parentheses")
        check(context("::f(\"(\", |)")?.argument == 1, "a quoted ( opens nothing")
        // What Return runs.
        func invocation(_ marked: String) -> String? {
            let st = caretState(marked)
            return context(marked).map { H.invocation(in: st.text, $0).text }
        }
        check(invocation("x ::today(3|) y") == "::today(3)", "a closed invocation as written")
        check(invocation("x ::today(3|  ") == "::today(3)", "a missing ) is filled in (trailing spaces dropped)")
        check(invocation("::coin(|") == "::coin()", "empty and unclosed")
        check(invocation(#"::ask("hi, |"#) == #"::ask("hi, ")"# && invocation("::f((1+2|") == "::f((1+2))", "open quote and parentheses closed")
        check(invocation("::ask('it|") == "::ask('it')", "the quote that opened")
        let unclosed = caretState("a ::today(3| ")
        check(context("a ::today(3| ").map { H.invocation(in: unclosed.text, $0).range } == NSRange(location: 2, length: 9), "range written")
    }))

    SelfTest.cases.append(("EditorKit.parameterHintVisibility", {
        typealias H = EditorLogic.ParameterHint
        var dismissed: Int?
        func hint(_ marked: String, list: Bool = false) -> H.Hint? { H.hint(caretState(marked), commands: hintCommands, listOpen: list, dismissed: &dismissed) }
        check(hint("Due ::today(|)")?.command.name == "today" && hint("Due ::today(|)")?.location == 4, "inside a known command")
        check(hint("Due ::date(|)")?.command.name == "today", "aliases")
        check(hint("::TODAY(|)")?.command.name == "today", "any case")
        check(hint("::nope(|)") == nil, "unknown commands get no hint")
        check(hint("::today(|)", list: true) == nil, "never with a list open")
        var selected = caretState("::today(3|)"); selected.selection.length = 1
        check(H.hint(selected, commands: hintCommands, listOpen: false, dismissed: &dismissed) == nil, "only with a bare caret")
        check(hint("x\n::today(|)\ny")?.location == 2, "on the caret's line")
        check(hint("::today(3)\n|") == nil, "another line: hidden")
        // Esc closes it for that invocation until the caret leaves it.
        dismissed = 4
        check(hint("Due ::today(3|)") == nil && dismissed == 4, "dismissed: stays closed while typing in it")
        check(hint("Due ::today(3)|") == nil && dismissed == nil, "leaving the parentheses forgets the dismissal")
        check(hint("Due ::today(3|)") != nil, "and it shows again")
        dismissed = 4
        check(hint("Due ::loan(1|)") == nil && dismissed == 4, "same place, same invocation start: still closed")
        check(hint("Du ::loan(1|)") != nil && dismissed == nil, "another invocation shows it")
    }))

    SelfTest.cases.append(("EditorKit.parameterHintText", {
        typealias H = EditorLogic.ParameterHint
        let today = hintCommands[0], loan = hintCommands[1], pick = hintCommands[2], coin = hintCommands[3]
        func line(_ c: ExtensionCommandInfo, _ argument: Int, empty: Bool = false) -> String { H.detail(c, argument: argument, isEmpty: empty).line }
        check(line(today, 0) == "days — how many days from today, e.g. 3 or -1 (default 0)", "summary, example and default")
        check(line(today, 1) == "format — iso, us or a pattern", "no example, no default")
        check(line(loan, 1) == "rate — yearly interest rate in percent, e.g. 6.5", "a required parameter shows no default")
        check(line(coin, 0, empty: true) == "Press Return to run", "no parameters")
        check(line(today, 0, empty: true) == "Press Return to use the defaults, or type to change them", "all optional, nothing typed")
        check(line(loan, 0, empty: true) == "principal — the amount borrowed", "required parameters: the first one's line")
        check(line(pick, 3) == "items — choices", "surplus arguments join a last text parameter")
        check(line(loan, 3) == "::loan takes 3 arguments; remove the extra one", "too many arguments")
        check(H.detail(today, argument: 0, isEmpty: false).name == "days" && H.detail(coin, argument: 0, isEmpty: true).name == nil,
              "the parameter's name is drawn apart")
        let pieces = H.signature(today, argument: 0)
        check(pieces.map(\.text).joined() == "::today(days = 0, format)", "signature with defaults")
        check(pieces == [H.Piece("::today(", .name), H.Piece("days", .optional, current: true), H.Piece(" = 0", .defaultValue),
                         H.Piece(", ", .name), H.Piece("format", .optional), H.Piece(")", .name)], "optional parameters and the current one")
        check(H.signature(loan, argument: 2).filter(\.current).map(\.text) == ["years"] && H.signature(loan, argument: 5).allSatisfy { !$0.current },
              "the current parameter; none past the last")
        check(H.signature(pick, argument: 4).filter(\.current).map(\.text) == ["items"], "a last text parameter stays current")
        check(H.signature(coin, argument: 0).map(\.text).joined() == "::coin()", "no parameters")
    }))

    SelfTest.cases.append(("EditorKit.parameterHintPlacement", {
        typealias H = EditorLogic.ParameterHint
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window = CGRect(x: 400, y: 300, width: 350, height: 400)
        let size = CGSize(width: 260, height: 44)
        let caret = CGRect(x: 520, y: 500, width: 1, height: 18)
        let above = H.frame(size: size, caret: caret, startX: 470, inset: 10, window: window, screen: screen)
        check(above.minY == caret.maxY + H.caretGap && above.minX == 460, "just above the caret, its text over the ::")
        let nearTop = CGRect(x: 520, y: 670, width: 1, height: 18)
        let below = H.frame(size: size, caret: nearTop, startX: 470, inset: 10, window: window, screen: screen)
        check(below.maxY == nearTop.minY - H.caretGap, "near the top of the window: below the caret")
        let right = H.frame(size: size, caret: caret, startX: 700, inset: 10, window: window, screen: screen)
        check(right.maxX == window.maxX - 6, "kept inside the note window when it fits")
        let wide = H.frame(size: CGSize(width: 500, height: 44), caret: caret, startX: 1300, inset: 10, window: window, screen: screen)
        check(wide.maxX <= screen.maxX - 4, "wider than the window: kept on the screen")
        let box = H.caretBox(line: CGRect(x: 10, y: 100, width: 1, height: 24), capHeight: 10, leading: 0)
        check(box.minY == 100 && box.height == 17.8 && box.minX == 10, "the caret's box sits on the line's foot")
    }))

    SelfTest.cases.append(("EditorKit.parameterHintEditing", {
        MainActor.assumeIsolated {
            let saved = Services.extensions
            defer { Services.extensions = saved }
            let fake = RecordingExtensions(hintCommands)
            Services.extensions = fake
            let editor = SuperNotesEditorFactory().makeEditor()
            editor.view.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
            guard let tv = editor.view.subviews.compactMap({ $0 as? NSScrollView }).first?.documentView as? NSTextView else {
                return check(false, "text view")
            }
            @MainActor func settle() {
                let deadline = Date().addingTimeInterval(1)
                while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)); if fake.runs.count > 0 { break } }
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            @MainActor func load(_ marked: String) {
                let st = caretState(marked)
                editor.load(Note(content: st.text))
                tv.setSelectedRange(st.selection)
                fake.runs = []
            }
            load("Who\n::coin(|)")
            tv.insertNewline(nil)
            settle()
            check(fake.runs.map(\.invocation) == ["::coin()"] && tv.string == "Who\nRAN", "Return inside ::coin(|) runs it: \(tv.string)")
            load("Due ::today(|)")
            tv.insertNewline(nil)
            settle()
            check(fake.runs.map(\.invocation) == ["::today()"] && tv.string == "Due RAN", "Return in empty parentheses runs with the defaults")
            load("x ::today(3|")
            tv.insertNewline(nil)
            settle()
            check(fake.runs.first?.invocation == "::today(3)" && fake.runs.first?.line == "x ::today(3)" && tv.string == "x RAN",
                  "a missing ) is filled in: \(fake.runs.map(\.invocation)) \(tv.string)")
            load("::loan(1, 2|, 3) and on")
            tv.insertNewline(nil)
            settle()
            check(fake.runs.map(\.invocation) == ["::loan(1, 2, 3)"] && tv.string == "RAN and on", "the invocation holding the caret")
            load("::nope(|)")
            tv.insertNewline(nil)
            check(fake.runs.isEmpty && tv.string == "::nope(\n)", "unknown names: Return is a new line")
            load("::loan(1, 2)|")
            tv.insertNewline(nil)
            settle()
            check(fake.runs.map(\.invocation) == ["::loan(1, 2)"], "after the ) Return still runs it")
            // ")" typed before the invocation's own ")" steps over it; inside nested parentheses it is typed.
            // The key goes to the editor first; what it leaves alone is typed (headless text views don't type keys).
            @MainActor func type(_ c: String) {
                let before = (tv.string, tv.selectedRange())
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                                characters: c, charactersIgnoringModifiers: c, isARepeat: false, keyCode: 29) {
                    tv.keyDown(with: event)
                }
                if (tv.string, tv.selectedRange()) == before { tv.insertText(c, replacementRange: tv.selectedRange()) }
            }
            load("::loan(1, 2|)")
            type(")")
            check(tv.string == "::loan(1, 2)" && tv.selectedRange().location == 12, "steps over the closing ): \(tv.string)")
            load("::loan((1+2|)")
            type(")")
            check(tv.string == "::loan((1+2))" && tv.selectedRange().location == 12, "closes a nested ( first: \(tv.string)")
            type(")")
            check(tv.string == "::loan((1+2))" && tv.selectedRange().location == 13, "then steps over")
            load("::nope(1|)")
            type(")")
            check(tv.string == "::nope(1))", "unknown names: typed as is")
        }
    }))

    SelfTest.cases.append(("EditorKit.longPillKeepsWindowSize", {
        MainActor.assumeIsolated {
            // The note window as the shell builds it (never shown): the editor's view pinned to the content view.
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 400),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            let editor = SuperNotesEditor()
            let content = NSView()
            window.contentView = content
            editor.view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(editor.view)
            NSLayoutConstraint.activate([
                editor.view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                editor.view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                editor.view.topAnchor.constraint(equalTo: content.topAnchor),
                editor.view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
            editor.load(Note(content: "Ask\n::ask(hello)"))
            window.layoutIfNeeded()
            let before = window.frame
            guard let pill = editor.view.subviews.compactMap({ $0 as? PillView }).first else { return check(false, "the note's pill") }
            editor.toast("Note saved", kind: .error)
            window.layoutIfNeeded()
            let oneLine = pill.frame.height
            let long = String(repeating: "The request failed because extensions may not use the network yet. ", count: 8)
            check(long.count > 500, "a 500-character message")
            editor.toast(long, kind: .error)
            window.layoutIfNeeded()
            check(window.frame == before, "a long message never resizes the window: \(window.frame) vs \(before)")
            check(pill.frame.height > oneLine * 1.8, "the pill grows taller instead: \(pill.frame.height) vs \(oneLine)")
            check(pill.frame.width <= editor.view.bounds.width - 16 && pill.frame.minX >= 0, "and stays inside the note: \(pill.frame)")
            check(pill.frame.height <= oneLine * 3.2, "three lines at most: \(pill.frame.height)")
            check(pill.toolTip == long, "the full message is in its tooltip")
            editor.toast("Note saved", kind: .info)
            window.layoutIfNeeded()
            check(pill.frame.height == oneLine && pill.toolTip == nil, "a short message is one line again, no tooltip")
        }
    }))

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
        check(wraps.x == 253 && wraps.wraps, "too long: wraps to a row below, against the column's right edge")
        check(A.wrappedX(width: 400, textStart: 44, textEnd: 293) == 44, "a result as wide as the column fills it from the start")
        check(A.hangingIndent(196, column: 150) == 75 && A.hangingIndent(28, column: 150) == 28 && A.hangingIndent(28, column: 0) == 0,
              "a hanging indent never takes more than half the column")
        let rtl = A.place(lineEnd: 100, width: 40, textStart: 44, textEnd: 293, rightToLeft: true)
        check(rtl.x == 60 && !rtl.wraps, "right-to-left: before the line end")
        check(A.place(lineEnd: 70, width: 40, textStart: 44, textEnd: 293, rightToLeft: true) == (44, true), "rtl wrap: the column's left edge")
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
            let editor = SuperNotesEditorFactory().makeEditor()
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
    // Soft wrap always holds: in every mode, at every width and text size, no line fragment, inline result or
    // frame runs past the visible width, and nothing scrolls sideways — after resizes too.
    SelfTest.cases.append(("EditorKit.softWrap", {
        MainActor.assumeIsolated {
            let saved = Services.analyzer
            Services.analyzer = NoteEngine()
            defer { Services.analyzer = saved }
            let editor = SuperNotesEditor()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled, .resizable],
                                  backing: .buffered, defer: false)
            window.contentView = editor.view
            let tv = editor.view.subviews.compactMap({ $0 as? NSScrollView }).first!.documentView as! NSTextView
            let scroll = tv.enclosingScrollView!
            let url = "https://example.com/a/very/long/path/that/never/breaks/" + String(repeating: "segment-", count: 20) + "end.html"
            let word = String(repeating: "x", count: 300)
            let notes: [(String, String)] = [
                ("plain url", "Notes\nsee " + url + " soon"),
                ("plain word", "Notes\n" + word + " done"),
                ("list", "list: Chores\n- " + String(repeating: "wash the car and sweep the porch ", count: 6) + "\n[ ] " + word),
                ("math", "math\n" + String(repeating: "123456789 + ", count: 12) + "1 =\n99999999999999 * 99999999999 =\nx = " + String(repeating: "1", count: 60) + "\nx * x ="),
                ("code", "code: swift\nlet path = \"" + url + "\"\nfunc " + word + "() {}"),
                ("sum", "sum\n" + String(repeating: "$1234567.89 ", count: 10) + "\n" + word),
                ("timer", "timer 25m\n" + word),
                ("markdown", "# " + String(repeating: "Heading ", count: 30) + "\n**" + word + "**\n`" + url + "`"),
                ("deep list", "list: Deep\n\t\t\t\t\t\t\t- seven tabs in, an item long enough to wrap a few times over\n"
                              + String(repeating: " ", count: 24) + "- twenty-four spaces in, another long item that wraps"),
                ("big results", "math\n2 ^ 200 =\n12345678901234 * 12345678901234 * 12345678901234 =\n5 feet in parsecs =\n1 + foo ="),
            ]
            @MainActor func verify(_ label: String) {
                editor.view.layoutSubtreeIfNeeded()
                tv.layoutManager!.ensureLayout(for: tv.textContainer!)
                let clip = scroll.contentView.bounds.width
                let column = tv.textContainer!.size.width
                check(abs(tv.frame.width - clip) < 0.5, "\(label): text view \(tv.frame.width) as wide as the clip \(clip)")
                check(column <= clip - 2 * tv.textContainerInset.width + 0.5, "\(label): container \(column) fits inside the view")
                check(scroll.contentView.bounds.origin.x == 0, "\(label): no sideways scroll")
                let lm = tv.layoutManager!
                let s = tv.string as NSString
                lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: lm.numberOfGlyphs)) { frag, used, _, range, _ in
                    check(used.maxX <= column + 0.5, "\(label): fragment \(range) used \(used) inside the column \(column)")
                    check(frag.maxX <= column + 0.5, "\(label): fragment \(range) \(frag) inside the column \(column)")
                    // A fragment holding visible characters lays them out (a paragraph indented past its column
                    // degenerates into empty fragments with their glyphs parked on the edge).
                    let chars = lm.characterRange(forGlyphRange: range, actualGlyphRange: nil)
                    var visible = false
                    for i in chars.location..<NSMaxRange(chars) where !CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(s.character(at: i)) ?? " ") {
                        // Hidden list markers are kerned to zero width.
                        if ((tv.textStorage?.attribute(.kern, at: i, effectiveRange: nil) as? CGFloat) ?? 0) >= 0 { visible = true; break }
                    }
                    check(!visible || (used.width > 1 && used.minX < column), "\(label): fragment \(range) '\(s.substring(with: chars).prefix(12))' laid out: \(used)")
                    // Every glyph, its advance included, ends inside the column (a degenerate layout parks glyphs on the edge).
                    for g in range.location..<NSMaxRange(range) where !lm.propertyForGlyph(at: g).contains(.controlCharacter) {
                        let ch = lm.characterIndexForGlyph(at: g)
                        guard ch < s.length, s.character(at: ch) != 10 else { continue }
                        let width = lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tv.textContainer!).width
                        let right = frag.minX + lm.location(forGlyphAt: g).x + width
                        if right > column + 0.5 {
                            check(false, "\(label): glyph \(g) '\(s.substring(with: NSRange(location: ch, length: 1)))' ends at \(right), past the column \(column)")
                            break
                        }
                    }
                }
                let (start, end) = editor.textColumn
                for r in editor.resultFrames {
                    check(r.minX >= start - 0.5 && r.maxX <= end + 0.5, "\(label): result \(r) inside the column \(start)–\(end)")
                }
            }
            for (name, text) in notes {
                editor.load(Note(content: text))
                for width in [240.0, 350.0, 600.0, 240.0] {
                    window.setContentSize(NSSize(width: width, height: 400))
                    verify("\(name) at \(Int(width)) pt")
                }
                editor.perform(.expandAllLinks)
                verify("\(name) at 240 pt, links expanded")
            }
            check((editor.view.subviews.compactMap { $0 as? NSScrollView }.first?.hasHorizontalScroller) == false, "no horizontal scroller")
            Defaults[.textSize] = .xl
            Defaults[.doubleFontSize] = true
            defer { Defaults.reset(.textSize); Defaults.reset(.doubleFontSize) }
            editor.load(Note(content: notes[3].1))
            for width in [600.0, 240.0, 350.0] {
                window.setContentSize(NSSize(width: width, height: 400))
                verify("xl double math at \(Int(width)) pt")
            }
        }
    }))
}
