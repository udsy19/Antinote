import AppKit
import Carbon.HIToolbox
import SuperNotesCore
import EditorKit
import ShellKit
import ToolsKit

/// The logic behind the Settings rows that change behaviour: list styles and check triggers, the "/" list,
/// keywords, slotted themes, menu shortcut rebinding, the dropdown window, timer alerts and export titles.
func registerSettingsBehaviourTests() {
    /// Runs `body` with `keys` set as given, then puts the user's values back.
    func with(_ values: [String: Any], _ body: () -> Void) {
        let snapshot = DefaultsSnapshot(Array(values.keys))
        for (name, value) in values { Defaults.store.set(value, forKey: name) }
        body()
        snapshot.restore()
    }

    SelfTest.cases.append(("Settings.keywords", {
        check(NoteMode.settingKeyword("math", in: "hello") == "math\nhello", "keyword goes on a new first line")
        check(NoteMode.settingKeyword("math", in: "sum\n1\n2") == "math\n1\n2", "an existing keyword line is replaced")
        check(NoteMode.settingKeyword("list", in: "") == "list\n", "empty note")
        with(["mainKeywords": try! JSONEncoder().encode(["math": "calc", "sum": "nope"])]) {
            check(NoteMode.math.mainKeyword == "calc", "chosen main keyword")
            check(NoteMode.sum.mainKeyword == "sum", "an unknown choice falls back to the first keyword")
        }
        with(["keywordsEnabled": false]) {
            check(NoteMode.detect(firstLine: "math").mode == .plain, "keywords off: every note is plain")
        }
        check(NoteMode.detect(firstLine: "math").mode == .math, "keywords back on")
        check(NoteMode.keywordModes.allSatisfy { !$0.summary.isEmpty }, "every keyword has a summary for the / list")
    }))

    SelfTest.cases.append(("Settings.typingOptions", {
        typealias T = TypingOption
        check(T.allCases.map(\.title) == ["Check Spelling While Typing", "Correct Spelling Automatically", "Check Grammar",
                                          "Capitalize Words Automatically", "Smart Quotes", "Smart Dashes", "Text Replacements"],
              "the menu's items, checkers first")
        check(T.checkSpelling.settingsTitle == "Check spelling while typing" && T.smartQuotes.settingsTitle == "Smart quotes",
              "Settings rows carry the same words in sentence case")
        check(Set(T.allCases.map(\.key.name)).count == T.allCases.count, "one key per option")
        check(T.checkSpelling.key.name == "checkSpelling" && T.textReplacements.key.name == "allowTextReplacements",
              "the existing keys are reused")
        check(T.allCases.filter(\.isChecker) == [.checkSpelling, .autocorrect, .checkGrammar], "the separator falls after the checkers")
        let keys = T.allCases.map(\.key.name)
        with(Dictionary(uniqueKeysWithValues: keys.map { ($0, false) })) {
            for option in T.allCases { Defaults.store.removeObject(forKey: option.key.name) }
            check(T.checkSpelling.isOn && T.allCases.filter { $0 != .checkSpelling }.allSatisfy { !$0.isOn },
                  "defaults: spelling checked, nothing else on")
            for option in T.allCases { option.isOn = true }
            check(T.allCases.allSatisfy { $0.isActive(in: .plain) && $0.isActive(in: .list) && $0.isActive(in: .timer) },
                  "everything applies in plain, list and timer notes")
            check(T.allCases.allSatisfy { !$0.isActive(in: .code) }, "code notes: nothing")
            check(T.checkSpelling.isActive(in: .math) && T.checkGrammar.isActive(in: .math) && T.autocorrect.isSuspended(in: .math),
                  "math notes: checked and no autocorrect")
            check([T.autoCapitalize, .smartQuotes, .smartDashes, .textReplacements].allSatisfy { $0.isSuspended(in: .math) },
                  "math notes: no substitutions")
            T.smartQuotes.isOn = false
            check(!T.smartQuotes.isActive(in: .plain) && Defaults[.smartQuotes] == false, "a switch written through the option")
        }
        check(T.suspensionNote(for: .code) == "Code notes: no checking or substitutions" && T.suspensionNote(for: .plain) == nil,
              "the menu's footer")
    }))

    SelfTest.cases.append(("Settings.slottedThemes", {
        with(["lightTheme": "fern", "darkTheme": "dune", "slottedLightTheme": "", "slottedDarkTheme": ""]) {
            check(Theme.selectedID(dark: false, slotted: true) == "fern", "slotted follows the ephemeral pair")
            Defaults[.slottedLightTheme] = "meadow"
            check(Theme.selectedID(dark: false, slotted: true) == "meadow", "slotted light has its own theme")
            check(Theme.selectedID(dark: true, slotted: true) == "dune", "slotted dark still follows")
            check(Theme.selectedID(dark: false, slotted: false) == "fern", "ephemeral unchanged")
        }
    }))

    SelfTest.cases.append(("Settings.unmodifiedNotes", {
        let cutoff = Date(timeIntervalSince1970: 1_000_000)
        let old = Note(modified: Date(timeIntervalSince1970: 10))
        check(old.isUnmodified(since: cutoff), "old ephemeral note")
        check(!Note(modified: Date(timeIntervalSince1970: 2_000_000)).isUnmodified(since: cutoff), "recent note")
        check(!Note(modified: old.modified, slot: 2).isUnmodified(since: cutoff), "slotted notes stay")
        check(!Note(modified: old.modified, isArchived: true).isUnmodified(since: cutoff), "archived notes stay")
        check(!Note(modified: old.modified, deletedAt: Date()).isUnmodified(since: cutoff), "already in The Void")
    }))

    SelfTest.cases.append(("Settings.listStyles", {
        typealias L = EditorLogic.Lists
        let bullets = L.normalizedListNote(TextState("list\nmilk\n# Shop\n[x] done\n// note"), style: .bullet)
        check(bullets.text == "list\n- milk\n# Shop\n[x] done\n// note", "default style bullets: \(bullets.text)")
        let numbers = L.normalizedListNote(TextState("list\na\nb"), style: .numbered)
        check(numbers.text == "list\n1. a\n2. b", "default style numbered renumbers: \(numbers.text)")
        check(L.normalizedListNote(TextState("list\na")).text == "list\n[ ] a", "checkboxes by default")
        check(L.cycled("a", start: .bullet) == "- a" && L.cycled("a", start: .numbered) == "1. a", "cycle starts at the default")
        check(L.cycled("a") == "[ ] a", "cycle default start")
        var options = L.Options()
        options.bullets = false
        check(options.item("- a") == nil && options.item("[ ] a") != nil && options.item("1. a") != nil, "bullets off")
        check(L.continued(TextState("- a", caret: 3), options: options) == nil, "a disabled marker doesn't continue")
        check(L.continued(TextState("- a", caret: 3), options: options.allMarkers)?.text == "- a\n- ", "list notes use every marker")
    }))

    SelfTest.cases.append(("Settings.checkTriggers", {
        typealias L = EditorLogic.Lists
        let box = ListLine.parse("[ ] milk /x")
        check(L.checkedByTrigger("[ ] milk /x", triggers: ["/x"], item: box, inListNote: false) == "[x] milk", "checkbox item")
        let bullet = ListLine.parse("  - bread/X")
        check(L.checkedByTrigger("  - bread/X", triggers: ["/x"], item: bullet, inListNote: false) == "  [x] bread",
              "bullets are checked as checkboxes, case-insensitively")
        check(L.checkedByTrigger("eggs /x", triggers: ["/x"], item: nil, inListNote: false) == nil, "plain lines outside lists")
        check(L.checkedByTrigger("eggs /x", triggers: ["/x"], item: nil, inListNote: true) == "[x] eggs", "list note lines")
        check(L.checkedByTrigger("# Shop /x", triggers: ["/x"], item: nil, inListNote: true) == nil, "headers stay")
        check(L.checkedByTrigger("[ ] milk done", triggers: ["/x", " done"], item: ListLine.parse("[ ] milk done"),
                                 inListNote: false) == "[x] milk", "custom triggers")
        let text = "list\n[ ] a /x\n[ ] b"
        let caret = ("list\n[ ] a /x" as NSString).length
        let kept = L.checkOffByTrigger(TextState(text, caret: caret), triggers: ["/x"], options: L.Options().allMarkers,
                                       inListNote: true, behavior: .keep)
        check(kept?.text == "list\n[x] a\n[ ] b" && kept?.selection.location == 10, "checked in place, caret after it")
        let moved = L.checkOffByTrigger(TextState(text, caret: caret), triggers: ["/x"], options: L.Options().allMarkers,
                                        inListNote: true, behavior: .moveToBottom)
        check(moved?.text == "list\n[ ] b\n[x] a", "checked item moves to the bottom: \(moved?.text ?? "nil")")
        check(L.checkOffByTrigger(TextState(text, caret: 7), triggers: ["/x"], options: L.Options(), inListNote: true,
                                  behavior: .keep) == nil, "only when the caret ends the line")
    }))

    SelfTest.cases.append(("Settings.slashToken", {
        typealias S = EditorLogic.Slash
        func token(_ text: String, emptyOnly: Bool = false) -> (NSRange, String)? {
            S.token(TextState(text, caret: (text as NSString).length), emptyLineOnly: emptyOnly).map { ($0.range, $0.query) }
        }
        check(token("/").map { $0.0 == NSRange(location: 0, length: 1) && $0.1.isEmpty } == true, "bare slash")
        check(token("hello /ma").map { $0.0 == NSRange(location: 6, length: 3) && $0.1 == "ma" } == true, "after a space")
        check(token("note\n  /ti")?.1 == "ti", "after indentation on a later line")
        check(token("[ ] /") != nil && token("- /su")?.1 == "su", "after a list marker")
        check(token("a/b") == nil && token("//") == nil && token("https://x") == nil, "not inside words, comments, URLs")
        check(token("/x y") == nil, "a space ends it")
        check(token("12 /", emptyOnly: true) == nil && token("  /", emptyOnly: true) != nil, "math notes: empty lines only")
        check(S.quickPick("3", query: "", rows: 5) == 2, "digit picks a row")
        check(S.quickPick("3", query: "a", rows: 5) == nil && S.quickPick("9", query: "", rows: 5) == nil
              && S.quickPick("0", query: "", rows: 5) == nil, "only 1…rows after a bare slash")
        let commands = [PaletteCommand(title: "New Note", symbol: "", action: {}),
                        PaletteCommand(title: "Insert Keyword: math", symbol: "", keyword: "math", action: {})]
        check(S.ordered(commands, query: "").map(\.title) == ["Insert Keyword: math", "New Note"], "keywords first")
        check(S.ordered(commands, query: "n").map(\.title) == ["New Note", "Insert Keyword: math"], "queries keep the ranking")
    }))

    SelfTest.cases.append(("Settings.vimMotionTimeout", {
        let engine = VimEngine()
        _ = engine.handle("d", text: "abc", selection: NSRange(location: 0, length: 0))
        check(engine.hasPendingInput, "an operator waits for its motion")
        engine.cancelPendingInput()
        check(!engine.hasPendingInput && engine.mode == .normal, "the timeout drops it")
        let out = engine.handle("x", text: "abc", selection: NSRange(location: 0, length: 0))
        check(out.text == "bc", "the next key starts a new command")
        _ = engine.handle("2", text: "abc", selection: NSRange(location: 0, length: 0))
        check(engine.hasPendingInput, "a count waits too")
    }))

    SelfTest.cases.append(("Settings.caretOffset", {
        let line = CGRect(x: 10, y: 0, width: 2, height: 20)
        let base = EditorLogic.caretRect(lineRect: line, capHeight: 10, leading: 0)
        let raised = EditorLogic.caretRect(lineRect: line, capHeight: 10, leading: 0, nudge: 2)
        check(raised.minY == base.minY - 2 && raised.height == base.height, "positive offsets raise the caret")
    }))

    SelfTest.cases.append(("Settings.menuShortcuts", {
        check(MenuLogic.bindingID(action: NSSelectorFromString("newNote:"), object: nil, tag: 0) == "newNote", "plain action")
        check(MenuLogic.bindingID(action: NSSelectorFromString("editorCommand:"), object: "findAndReplace", tag: 0)
              == "editorCommand.findAndReplace", "editor commands by name")
        check(MenuLogic.bindingID(action: NSSelectorFromString("openSlotItem:"), object: nil, tag: 0) == "openSlotItem.0",
              "slot items by slot")
        let builtIn = MenuLogic.shortcut(builtIn: "n", .command, override: nil)
        check(builtIn.0 == "n" && builtIn.1 == .command, "no override keeps the built-in shortcut")
        let removed = MenuLogic.shortcut(builtIn: "n", .command, override: .some(nil))
        check(removed.0.isEmpty && removed.1.isEmpty, "a removed shortcut")
        let up = Shortcut(key: kVK_UpArrow, modifiers: [.option, .function])
        let rebound = MenuLogic.shortcut(builtIn: "n", .command, override: .some(up))
        check(rebound.0 == MenuLogic.upArrow && rebound.1 == .option, "arrows map to their function key; fn is dropped")
        check(Shortcut(keyEquivalent: MenuLogic.upArrow, modifiers: .option)?.keyCode == UInt32(kVK_UpArrow), "back to the key")
        if let n = Shortcut(keyEquivalent: "n", modifiers: .command) {
            check(n.keyEquivalent == "n" && n.displayString.hasSuffix("N"), "letters round-trip through the layout")
        } else {
            check(false, "a key types “n”")
        }
        check(MenuLogic.exportRows(enabled: [.customURL, .bear], quick: nil)
              == [.destination("Send to Bear", .bear), .destination("Custom Export", .customURL)], "custom URL destination")
    }))

    SelfTest.cases.append(("Settings.dropdownLayout", {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let anchor = CGRect(x: 1000, y: 875, width: 24, height: 24)
        let f = DropdownLayout.frame(size: CGSize(width: 400, height: 500), minimum: CGSize(width: 240, height: 180),
                                     anchor: anchor, visible: screen)
        check(f.size == CGSize(width: 400, height: 500) && f.midX == anchor.midX && f.maxY == anchor.minY - 4,
              "centred 4 pt under the status item: \(f)")
        let tiny = DropdownLayout.frame(size: CGSize(width: 10, height: 10), minimum: CGSize(width: 240, height: 180),
                                        anchor: anchor, visible: screen)
        check(tiny.size == CGSize(width: 240, height: 180), "never below the window's minimum")
        let edge = DropdownLayout.frame(size: CGSize(width: 400, height: 300), minimum: .zero,
                                        anchor: CGRect(x: 1430, y: 875, width: 10, height: 24), visible: screen)
        check(edge.maxX == screen.maxX - 6, "kept 6 pt inside the screen")
    }))

    SelfTest.cases.append(("Settings.exportTitles", {
        let utc = TimeZone(identifier: "UTC")!
        check(ExportText.datedTitle(Date(timeIntervalSince1970: 0), timeZone: utc) == "Super Notes - 1970-01-01 00-00-00",
              "dated title")
        check(ExportText.customURL(template: "app://new?t={TITLE}&b={CONTENT}&d={DATE}", title: "A b", content: "x&y",
                                   date: "2026") == "app://new?t=A%20b&b=x%26y&d=2026", "placeholders are encoded")
        check(ExportText.customURL(template: "  ", title: "", content: "", date: "") == nil, "blank template")
    }))

    SelfTest.cases.append(("Settings.timerAlerts", {
        with(["countdownNotification": true, "countdownFullScreen": false, "countdownSound": true,
              "pomodoroNotification": false, "pomodoroFullScreen": true, "pomodoroSound": false]) {
            check(TimerAlert.settings(for: .finished, kind: .countdown(60))
                  == TimerAlert(notification: true, fullScreen: false, sound: true), "countdown settings")
            check(TimerAlert.settings(for: .workEnded(1), kind: .pomodoro(work: 1500, rest: 300))
                  == TimerAlert(notification: false, fullScreen: true, sound: false), "pomodoro settings")
            check(TimerAlert.settings(for: .workEnded(1), kind: .pomodoro(work: 20, rest: 300)) == .none,
                  "sessions of 30 seconds or less stay quiet")
            check(TimerAlert.settings(for: .breakEnded(1), kind: .pomodoro(work: 20, rest: 300)) != .none,
                  "a long break still alerts")
        }
    }))
}

/// The find shelf's matching (match case, match types, replace).
func registerFindShelfTests() {
    SelfTest.cases.append(("EditorKit.findShelf", {
        typealias F = EditorLogic.Find
        let text = "Cat catalog cat. Bobcat"
        func found(_ term: String, _ options: F.Options) -> [Int] { F.matches(of: term, in: text, options: options).map(\.location) }
        check(found("cat", F.Options()) == [0, 4, 12, 20], "contains, any case")
        check(found("cat", F.Options(matchCase: true)) == [4, 12, 20], "Aa matches case")
        check(found("cat", F.Options(type: .matchesWord)) == [0, 12], "whole words")
        check(found("cat", F.Options(type: .startsWith)) == [0, 4, 12], "word starts")
        check(found("cat", F.Options(type: .endsWith)) == [0, 12, 20], "word ends")
        check(found("c.t", F.Options(type: .regex)) == [0, 4, 12, 20], "regex")
        check(found("c.t", F.Options()) == [], "literal dots outside regex")
        check(found("(", F.Options(type: .regex)) == [], "an invalid regex finds nothing")
        let matches = F.matches(of: "cat", in: text, options: F.Options())
        check(F.next(from: 5, in: matches, backwards: false) == 2 && F.next(from: 21, in: matches, backwards: false) == 0,
              "next wraps around")
        check(F.next(from: 4, in: matches, backwards: true) == 0 && F.next(from: 0, in: matches, backwards: true) == 3,
              "previous wraps around")
        let all = F.replacingAll("cat", with: "dog", in: text, options: F.Options(type: .matchesWord))
        check(all.text == "dog catalog dog. Bobcat" && all.count == 2, "replace all words")
        check(F.replacingAll("(\\w)at", with: "$1og", in: "cat hat", options: F.Options(type: .regex)).text == "cog hog",
              "regex templates")
        check(F.replacingAll("a", with: "$1", in: "a", options: F.Options()).text == "$1", "plain replacements are literal")
        check(F.replacement(for: NSRange(location: 0, length: 3), in: "cat", term: "(c)at", with: "$1ow",
                            options: F.Options(type: .regex)) == "cow", "one regex replacement")
    }))
}
