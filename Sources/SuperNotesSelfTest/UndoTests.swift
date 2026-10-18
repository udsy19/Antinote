import AppKit
import SuperNotesCore
import EditorKit
import NoteEngine
import ShellKit
import StorageKit

/// A store, an analyzer and an editor in a window that never comes on screen (shared with `SlotsTests`).
@MainActor
final class Bench {
    let window: NSWindow
    let editor: SuperNotesEditor
    let tv: NSTextView
    let store: SQLiteNoteStore
    let dir: URL
    let suite = "supernotes.selftest.undo.\(UUID().uuidString)"
    let savedDefaults: UserDefaults

    init() {
        savedDefaults = Defaults.store
        Defaults.store = UserDefaults(suiteName: suite)!
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("supernotes-undo-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = try! SQLiteNoteStore(url: dir.appendingPathComponent("notes.sqlite"),
                                     backupsFolder: dir.appendingPathComponent("backups"))
        Services.store = store
        Services.analyzer = NoteEngine()
        Services.editorFactory = SuperNotesEditorFactory()
        editor = SuperNotesEditor()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320), styleMask: [.titled],
                          backing: .buffered, defer: false)
        window.contentView = editor.view
        editor.view.layoutSubtreeIfNeeded()
        tv = editor.view.subviews.compactMap({ $0 as? NSScrollView }).first!.documentView as! NSTextView
        window.makeFirstResponder(tv)
    }

    func load(_ content: String) -> Note {
        let note = store.create(content: content)
        editor.load(note)
        return note
    }

    func type(_ s: String) { for ch in s { tv.insertText(String(ch), replacementRange: tv.selectedRange()) } }
    func caret(_ at: Int) { tv.setSelectedRange(NSRange(location: at, length: 0)) }
    /// Edit › Undo / Redo: nil-targeted actions that start at the window's first responder.
    @discardableResult func undo() -> Bool { window.firstResponder?.tryToPerform(NSSelectorFromString("undo:"), with: nil) ?? false }
    @discardableResult func redo() -> Bool { window.firstResponder?.tryToPerform(NSSelectorFromString("redo:"), with: nil) ?? false }
    func key(_ chars: String, code: UInt16, flags: NSEvent.ModifierFlags = []) {
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                                 context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        tv.keyDown(with: e)
    }
    func spin(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    var text: String { tv.string }
    var selection: NSRange { tv.selectedRange() }
    /// What the Edit menu would show: the item's title after the first responder validated it.
    static func menuTitle(_ action: String, in window: NSWindow) -> String {
        let item = NSMenuItem(title: "", action: NSSelectorFromString(action), keyEquivalent: "")
        guard let target = window.firstResponder as? NSUserInterfaceValidations, target.validateUserInterfaceItem(item) else { return "" }
        return item.title
    }
    var undoTitle: String { Self.menuTitle("undo:", in: window) }
    var redoTitle: String { Self.menuTitle("redo:", in: window) }
    var manager: UndoManager { editor.activeUndoManager }

    func cleanup() {
        Defaults.store = savedDefaults
        UserDefaults().removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: dir)
    }
}

/// Undo and redo driven through the real editor offscreen: Edit › Undo / Redo sent down the responder chain of a
/// window holding the editor (what ⌘Z, ⇧⌘Z and ⌘Y do), typing groups, every programmatic edit as one step that
/// puts the selection back, one history per note, autosave, Vim's u / ⌃R and Undo Delete Note in the shell.
func registerUndoTests() {
    SelfTest.cases.append(("EditorKit.typingCoalescing", {
        func extends(_ typed: String, _ caret: Int, _ old: String, _ new: String, after: TimeInterval = 0.1) -> Bool {
            TypingCoalescing.extends(typed: typed, caret: caret, old: old, new: new, elapsed: after)
        }
        check(extends("hell", 4, "hell", "hello"), "a letter joins the word")
        check(extends("Oh", 2, "Ohello", "Ohhello"), "a repeated letter joins at the caret")
        check(!extends("Oh", 3, "Ohello", "Ohhello"), "but not away from it")
        check(!extends("hello", 5, "hello", "hello "), "a space ends the word")
        check(extends(" ", 6, "hello ", "hello w"), "the next word starts after the space")
        check(extends("a", 1, "a", ""), "backspace joins the group")
        check(extends("", 2, "abc", "ab"), "forward delete joins the group")
        check(!extends("ab", 2, "ab", "abcd"), "a paste is not typing")
        check(!extends("a\n", 2, "a\n", "a\nb"), "a line break ends the group")
        check(!extends("ab", 2, "ab", "abc", after: TypingCoalescing.pause + 1), "a pause ends the group")
        check(!extends("ab", 0, "ab", "abc"), "typing elsewhere starts anew")
        check(TypingCoalescing.caretAfter(before: NSRange(location: 1, length: 0), old: "Ohello", new: "Ohhello", live: 0) == 2,
              "the caret lands after the typed character even when the text view has not settled")
        check(TypingCoalescing.caretAfter(before: NSRange(location: 0, length: 5), old: "hello x", new: "Hi x", live: 2) == 2, "typing over a selection")
        check(TypingCoalescing.caretAfter(before: NSRange(location: 2, length: 0), old: "aaa", new: "aa", live: 2) == 2, "forward delete keeps the caret")
        check(TypingCoalescing.caretAfter(before: NSRange(location: 2, length: 0), old: "aaa", new: "aa", live: 1) == 1, "backspace moves it back")
    }))

    SelfTest.cases.append(("EditorKit.undoTyping", {
        MainActor.assumeIsolated {
            let b = Bench()
            defer { b.cleanup() }
            _ = b.load("hello")
            check(b.tv.undoManager == nil, "the text view keeps no undo manager of its own (the editor owns undo)")
            check(b.manager.canUndo == false, "a freshly loaded note has nothing to undo")
            b.type(" world")
            check(b.undoTitle == "Undo Typing", "menu title: \(b.undoTitle)")
            check(b.undo() && b.text == "hello" && b.selection == NSRange(location: 5, length: 0), "⌘Z takes the word back: \(b.text) \(b.selection)")
            check(b.redoTitle == "Redo Typing", "redo title: \(b.redoTitle)")
            check(b.redo() && b.text == "hello world" && b.selection == NSRange(location: 11, length: 0), "⇧⌘Z / ⌘Y put it back: \(b.text)")
            b.type(" again")
            b.undo()
            check(b.text == "hello world", "typing after redo undoes to the redone text: \(b.text)")
            b.undo()
            check(b.text == "hello", "each word is a step: \(b.text)")
            b.redo(); b.redo()
            check(b.text == "hello world again", "redo walks forward: \(b.text)")
            b.caret(0)
            b.type("Oh ")
            b.undo()
            check(b.text == "Ohhello world again", "a space after a word starts the next step: \(b.text)")
            b.undo()
            check(b.text == "hello world again" && b.selection == NSRange(location: 0, length: 0), "moving the caret started a new step; undo restores the caret")
            b.tv.setSelectedRange(NSRange(location: 0, length: 5))
            b.type("Hi")
            check(b.text == "Hi world again", "typing over a selection")
            b.undo()
            check(b.text == "hello world again" && b.selection == NSRange(location: 0, length: 5), "undo restores the replaced selection: \(b.selection)")
        }
    }))

    SelfTest.cases.append(("EditorKit.undoListNote", {
        MainActor.assumeIsolated {
            let b = Bench()
            defer { b.cleanup() }
            _ = b.load("todo\nmilk")
            check(b.text == "todo\n[ ] milk", "list note normalized on load")
            b.caret(b.text.utf16.count)
            b.tv.insertNewline(nil)   // Return: list continuation adds the next item
            check(b.text == "todo\n[ ] milk\n[ ] " && b.undoTitle == "Undo New Item", "Return continues the list as one step: \(b.text.debugDescription) \(b.undoTitle)")
            b.type("eggs")
            check(b.text == "todo\n[ ] milk\n[ ] eggs", "the marker rewrite lands with the typing: \(b.text.debugDescription)")
            b.undo()
            check(b.text == "todo\n[ ] milk\n[ ] ", "undo takes the word, keeps the item: \(b.text.debugDescription)")
            b.undo()
            check(b.text == "todo\n[ ] milk" && b.selection == NSRange(location: 13, length: 0), "undo takes the new item with its marker: \(b.text.debugDescription)")
            b.redo(); b.redo()
            check(b.text == "todo\n[ ] milk\n[ ] eggs", "redo rebuilds both steps: \(b.text.debugDescription)")
            b.undo(); b.undo()
            check(b.manager.canUndo == false && b.text == "todo\n[ ] milk", "back at the loaded text, nothing left to undo")
        }
    }))

    SelfTest.cases.append(("EditorKit.undoCommands", {
        MainActor.assumeIsolated {
            let b = Bench()
            defer { b.cleanup() }
            _ = b.load("todo\nmilk\neggs")
            let start = b.text
            @MainActor func roundTrip(_ command: EditorCommand, named: String, caret: Int, expect: (String) -> Bool) {
                b.caret(caret)
                b.editor.perform(command)
                let after = b.text, sel = b.selection
                check(expect(after), "\(named): \(after.debugDescription)")
                check(b.undoTitle == "Undo \(named)", "\(named) is named in the Edit menu: \(b.undoTitle)")
                b.undo()
                check(b.text == start && b.selection == NSRange(location: caret, length: 0), "undo \(named) restores text and caret: \(b.selection)")
                b.redo()
                check(b.text == after && b.selection == sel, "redo \(named) restores its selection: \(b.selection)")
                b.undo()
            }
            roundTrip(.toggleCheckbox, named: "Check Off Item", caret: 9) { $0 == "todo\n[x] milk\n[ ] eggs" }
            roundTrip(.moveLineDown, named: "Move Line", caret: 9) { $0 == "todo\n[ ] eggs\n[ ] milk" }
            roundTrip(.duplicateLineDown, named: "Duplicate Line", caret: 9) { $0 == "todo\n[ ] milk\n[ ] milk\n[ ] eggs" }
            roundTrip(.indent, named: "Indent", caret: 9) { $0 == "todo\n\t[ ] milk\n[ ] eggs" }
            roundTrip(.cycleListStyle, named: "Change List Style", caret: 9) { $0 != start }

            _ = b.load("plain note")
            b.caret(5)
            b.editor.insert(" new")
            check(b.text == "plain new note" && b.undoTitle == "Undo Insert", "insert is one named step: \(b.undoTitle)")
            b.undo()
            check(b.text == "plain note" && b.selection == NSRange(location: 5, length: 0), "undo insert: \(b.text)")
            b.caret(10)
            b.editor.perform(.strikethrough)
            check(b.undoTitle == "Undo Strikethrough", "strikethrough named: \(b.undoTitle)")
            b.undo()
            check(b.text == "plain note", "undo strikethrough: \(b.text)")
        }
    }))

    SelfTest.cases.append(("EditorKit.undoPerNote", {
        MainActor.assumeIsolated {
            let b = Bench()
            defer { b.cleanup() }
            let a = b.load("alpha")
            b.type(" one")
            let other = b.load("beta")
            check(b.manager.canUndo == false, "another note starts with its own, empty history")
            b.type(" two")
            b.undo()
            check(b.text == "beta", "undo in the second note touches only it: \(b.text)")
            b.undo()
            check(b.text == "beta", "never undoes into another note's text")
            b.editor.load(b.store.note(a.id)!)
            check(b.text == "alpha one" && b.manager.canUndo == true, "the first note keeps its history for the session")
            b.undo()
            check(b.text == "alpha", "its step undoes: \(b.text)")
            b.editor.load(b.store.note(other.id)!)
            check(b.manager.canRedo == true, "the second note kept its redo")
            b.redo()
            check(b.text == "beta two", "redo in the second note: \(b.text)")
            var changed = b.store.note(a.id)!
            changed.content = "alpha changed elsewhere"
            b.store.update(changed)
            b.editor.load(changed)
            check(b.manager.canUndo == false && b.manager.canRedo == false,
                  "a note changed elsewhere starts afresh instead of undoing into stale text")
        }
    }))

    SelfTest.cases.append(("EditorKit.undoSurvivesAutosave", {
        MainActor.assumeIsolated {
            let b = Bench()
            defer { b.cleanup() }
            let note = b.load("saved")
            b.type(" text")
            b.spin(0.5)
            check(b.store.note(note.id)?.content == "saved text", "the debounced save wrote the note")
            check(b.text == "saved text" && b.manager.canUndo == true, "saving leaves the text and history alone")
            b.undo()
            check(b.text == "saved", "undo after autosave: \(b.text)")
            b.spin(0.5)
            check(b.store.note(note.id)?.content == "saved", "the undone text is saved too")
            b.redo()
            check(b.text == "saved text", "redo after the second save: \(b.text)")
        }
    }))

    SelfTest.cases.append(("EditorKit.undoVim", {
        MainActor.assumeIsolated {
            let b = Bench()
            defer { b.cleanup() }
            Defaults[.vimMode] = true
            _ = b.load("vim note")
            b.key("", code: 53)                 // Esc → normal mode
            b.key("x", code: 7)                 // delete the character under the caret
            let cut = b.text
            check(cut != "vim note", "x deletes: \(cut)")
            b.key("u", code: 32)
            check(b.text == "vim note", "u undoes the Vim edit: \(b.text)")
            b.key("r", code: 15, flags: .control)
            check(b.text == cut, "⌃R redoes it: \(b.text)")
            Defaults[.vimMode] = false
        }
    }))

    SelfTest.cases.append(("EditorKit.pillAvoidsCaret", {
        MainActor.assumeIsolated {
            let b = Bench()
            defer { b.cleanup() }
            guard let pill = b.editor.view.subviews.compactMap({ $0 as? PillView }).first else { return check(false, "pill view") }
            _ = b.load("short")
            b.editor.toast("Hello")
            b.editor.view.layoutSubtreeIfNeeded()
            check(pill.frame.minY < 40, "with the caret high the pill sits at the bottom: \(pill.frame)")
            _ = b.load(Array(repeating: "line", count: 60).joined(separator: "\n"))
            b.tv.scrollRangeToVisible(b.selection)
            b.editor.toast("Hello")
            b.editor.view.layoutSubtreeIfNeeded()
            check(pill.frame.minY > b.editor.view.bounds.midY, "with the caret on the last line the pill moves to the top: \(pill.frame)")
        }
    }))

    SelfTest.cases.append(("ShellKit.undoDeleteNote", {
        MainActor.assumeIsolated {
            let b = Bench()
            defer { b.cleanup() }
            Defaults[.suppressedWarnings].insert("shellKit.moveToVoid")
            let older = b.store.create(content: "older note")
            let front = b.store.create(content: "front note")
            _ = WindowPreview.frameView(revealed: false)
            check(WindowPreview.currentNoteID == front.id, "the front note is shown")
            let edit = WindowPreview.mainMenu!.items.first { $0.title == "Edit" }!.submenu!
            let undoAction = NSSelectorFromString("undo:"), redoAction = NSSelectorFromString("redo:")
            let redos = edit.items.filter { $0.action == redoAction }
            check(redos.map(\.keyEquivalent) == ["z", "y"] && redos[1].isHidden && redos[1].allowsKeyEquivalentWhenHidden,
                  "Redo answers to ⇧⌘Z and, through a hidden twin, ⌘Y")
            check(edit.items.first?.keyEquivalent == "z" && edit.items.first?.action == undoAction, "Undo ⌘Z leads the Edit menu")

            WindowPreview.deleteCurrentNote()
            check(b.store.note(front.id)?.isInVoid == true, "Delete Note sends the note to The Void")
            check(WindowPreview.currentNoteID == older.id, "the next note is shown")
            let shellWindow = WindowPreview.window
            check(shellWindow.firstResponder is NSTextView, "the note's text has the focus after deleting")
            check(Bench.menuTitle("undo:", in: shellWindow) == "Undo Delete Note", "⌘Z offers Undo Delete Note: \(Bench.menuTitle("undo:", in: shellWindow))")
            check(shellWindow.firstResponder?.tryToPerform(undoAction, with: nil) == true, "undo reaches the shell")
            check(b.store.note(front.id)?.isInVoid == false && WindowPreview.currentNoteID == front.id, "the note is back and shown")
            check(Bench.menuTitle("undo:", in: shellWindow) == "", "nothing to undo right after the restore (no redo-delete either)")
            // Typing in the next note moves on: the deleted note stays in The Void.
            WindowPreview.deleteCurrentNote()
            check(WindowPreview.currentNoteID == older.id, "deleted again")
            let tv = WindowPreview.window.firstResponder as? NSTextView
            tv?.insertText("x", replacementRange: tv!.selectedRange())
            check(Bench.menuTitle("undo:", in: shellWindow) == "Undo Typing", "after typing ⌘Z undoes the typing: \(Bench.menuTitle("undo:", in: shellWindow))")
            check(b.store.note(front.id)?.isInVoid == true, "the deleted note stays in The Void")
        }
    }))
}
