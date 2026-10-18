# UX audit — end to end

Every flow walked with one question: does anything get between the person and the note? Issues are fixed in the
same change unless the status says otherwise. Behaviour is covered by self-tests (`.build/debug/SuperNotesSelfTest`),
visuals by offscreen renders (`.build/debug/SuperNotesRender <dir> <scene-prefix…>`).

| Flow | Issue found | Fix | Status |
| --- | --- | --- | --- |
| Typing, undo | ⌘Z corrupted the text in list notes and then did nothing: the text view's range-based typing coalescer lost track when the editor rewrote a list marker or shortened a link inside a keystroke. No ⌘Y. | The editor records its own history (`NoteHistory`): whole-state steps, typing grouped per word, named steps for every command, one history per note, a hidden Redo twin on ⌘Y. Vim `u` / ⌃R use it; ⌘Z after Delete Note restores the note. | Fixed — `UndoTests.swift` (typing, list notes, commands, per-note, autosave, Vim, delete) |
| Delete a note | Three names for one action ("Delete Note", "Send to The Void", "banished to void"); the confirmation's button said "Send to The Void"; nothing said it could be undone. | One verb: menu "Delete Note", palette "Delete Note", pills "Note deleted" / "N notes deleted", alert "Delete this note?" with a Delete button, pill "Note deleted · ⌘Z to undo". | Fixed — `ShellKit.undoDeleteNote` |
| The Void | Restore was an unlabeled arrow icon; "lost souls", "Lost 3 hours ago", "(Empty vessel)", "Return", "There is no recovery beyond The Void." | A labeled Restore button per row, "Deleted 3 hours ago", "4 deleted notes", "(Empty note)", Done, "This can't be undone." Empty state says what the place is for. | Fixed — renders `void-list`, `void-empty` |
| Top / bottom bars | A bar revealed by a resting pointer stayed over the text while typing. | A plain keystroke in the note takes both bars down; they come back once the pointer really moves (4 pt). | Fixed — `HoverBar.typingStarted` |
| Message pills | The editor's pill sat at the bottom even when the caret's line was down there, covering what was being typed. | The pill moves to the top (below the title bar) while the caret's line is in the pill's strip. | Fixed — `EditorKit.pillAvoidsCaret` |
| Pill copy | Mixed endings ("Extracted text.", "Pasted content optimized."), system-side wording ("Cannot partially edit shortened links. Expand before editing."), and "Calculated results can't be edited." with no way out. | No trailing periods; say what to do: "Click the link to expand it before editing", "“Prevent editing answers” is on in Settings → Keywords", "Pasted text cleaned up", "Text captured", "AutoPaste on · Esc stops", "Couldn't read that image. Try copying and pasting it". | Fixed |
| Move to front | Menu "Move Note to Front", palette "Promote to Front", pills "Promoted note to front" / "Note is already first" / "Slotted notes don't have a front position". | "Move to Front" everywhere; pills "Moved to the front", "Already at the front", "Slotted notes stay in their slot". Pin: "Pinned on top" / "Unpinned" in both places. | Fixed |
| Timers | A finished timer's full-screen alert activated Super Notes and took the keyboard mid-sentence in another app. | The alert comes forward without taking focus; clicking it (or Nice / Esc once it's clicked) dismisses it. Break, breathing and live screens, which you ask for, still take focus. | Fixed — `TimerOverlay.present(takesFocus:)` |
| Menus | Support and Help menus listed the same two items. | One Help menu. A self-test checks the menu bar order and that no two visible items share a shortcut (⌘Y lives only on the hidden Redo twin). | Fixed — `ShellKit.menuShortcutsUnique` |
| Settings → Appearance | "Show note modified/created time" and "Show the note creation date" read as the same thing; the first adds the time of day, the second switches to the creation date. | "Show the time of day next to the date", "Date the note by when it was created, not last changed". | Fixed — render `settings-full-appearance` |
| Onboarding | Final note: "⌘D Send a note to The Void". | "Delete a note (it waits in The Void)". | Fixed |
| First launch + tutorial | Tutorial notes seed once, walk back with ⌘[ hints, keyword demos live. | — | OK as is |
| Show / hide with ⌥A | `showMain` → `focusActive` puts the caret back in the text view, which keeps its selection. "Create a new note after" is a setting (Never by default). | — | OK as is |
| Keyword modes | Math results are drawn after the line (annotations), never inserted; ⌥-click inserts one on purpose. Return on an empty item ends the list (`Lists.continued`); an indented empty item outdents first. | — | OK as is |
| "/" and "::" lists | The "/" list opens only at the start of a line or after a space, with letters and digits after it; never in URLs ("https://"), fractions ("1/2") or paths with no matching command. Esc closes it and remembers the dismissal for that "/". `::` likewise. Neither takes the focus; the mouse works. | — | OK as is |
| Find bar | ⇧⌘F docks the shelf; Esc / Done close it and put the focus and the found match back in the text. | — | OK as is |
| Swiping, ⌘[ / ⌘] | Past the newest note a new one is created with a "New note created" pill; "This is the oldest note" / "Already at latest" otherwise. Non-blocking. | — | OK as is |
| Slots bar | Crisp planets over glass, tips name the shortcut for an empty slot. | — | OK as is (1.3.2) |
| Locked notes | Lock screen with a labeled Unlock button; relock timing in Settings → Notes. | — | OK as is |
| Export, print | "Note exported", "No note to print", "Choose a Quick Export destination in Settings → Export". | — | OK as is |
| Settings | Sentence-case labels with captions; every control bound to a default; no dead controls found in a pass over all panes. | — | OK as is |
| Window | Min size 240 × 180, frame remembered (not in dropdown mode), pin on top, translucency behind the note. | — | OK as is |
| Settings, search and palette fields | Standard field editors; the Edit menu's nil-targeted Undo / Redo reach them through their key panel. | — | OK as is |

## Not changed, on purpose

- The delete confirmation stays (it can be suppressed with "Don't ask again"): ⌘Z now covers the common slip, the
  alert covers the deliberate one.
- Keyword and command names keep their established vocabulary ("The Void", "Ephemeral", slots as planets); the
  audit changed what was inconsistent or unlabeled, not what gives the app its character.
