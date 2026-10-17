# EditorKit — the note editor

EditorKit implements `NoteEditing` (`JotterEditor`) and registers `Services.editorFactory`
(`EditorKitModule.install()`). ShellKit embeds `editor.view`, calls `load(_:)`, forwards menu commands through
`perform(_:)` and shows `onAnalysis` output in its chrome.

Evidence comes from the original app's class list (`TextEditorView.Coordinator`, `TextEditorViewWrapper : NSTextView`,
`ChecklistManager`, `AntilinkManager`, `RoundedCodeLayoutManager : NSLayoutManager`, `FindAndReplaceManager`,
`AutoPasteMonitor`, `DropReceivingView`, `ExtensionAutocompleteManager`, `VimModePreferences`, `UndoManagement`) and
its UI strings (quoted below).

## Text system

- `NSTextView` on **TextKit 1** (explicit `NSTextStorage` → `NSLayoutManager` → `NSTextContainer`), like the original's
  `RoundedCodeLayoutManager`. TextKit 1 gives stable glyph rects for drawing checkboxes, results and code backgrounds.
- Plain text only: `isRichText = false`, every paste goes through our paste pipeline, no `.link` attributes.
- Styling is recomputed from the plain text after each edit (attributes only, never characters).
- Font: `Typography.font()` — `Defaults[.fontName]` (Menlo) at the `Defaults[.textSize]` preset (XS 11, S 12.5,
  M 13.5, L 16, XL 18), doubled by `Defaults[.doubleFontSize]`. Line pitch 1.6 × the size (+ `Defaults[.lineSpacing]`);
  list notes use 1.35 × with 0.65 × extra between items. "Increase/Decrease Text Size" step through the presets;
  reset restores M.
- Theme colours from `Theme.current` roles (see ui-reference.md §0); restyles on `Theme.didChange`, appearance
  changes and relevant `Defaults` keys. Caret: 2 pt rounded, `accent1Main`, ascender to descender. Selection:
  `typeHighlight`. Scroller: a thin 3 pt `typeHighlight` knob.
- Paper (`Defaults[.paperType]`, `[.paperOpacity]` = the theme's `gridSuperlight` / `gridClear` / `gridBold`):
  lines on the text rows, small (20 pt) / large (40 pt) grid, or 1.5 pt dots on the 20 pt lattice.
- RTL: `Defaults[.forceRTL]` sets right-to-left base writing direction (results then draw on the left).
- Insets: text 44 pt from the window sides (scaled with the font), first line's capitals ~37 pt down; list markers
  sit in the left gutter (12.5 pt boxes 20.5 pt from the edge). On the keyword line only the keyword is coloured
  (`Theme.keyword(_:)`: math accent 1, list accent 2, sum/paste accent 3, avg/code/timer accent 4, count accent 5);
  a timer command line is coloured whole.
- Markdown: `#`/`##`/`###` lines bold in accent 1 main/secondary/tertiary (hashes kept); `**bold**`, `*italic*`,
  `__underline__`, `~~strike~~` keep their markers, dimmed to `typeLight`; `// comments` italic `typeLight`;
  inline `` `code` `` and fenced blocks on a `backgroundFade` rounded rect. Code tokens: keywords accent 2,
  strings accent 3, numbers accent 4, comments `typeLight`.
- Message pills (`PillView`, shared with `HUD`): bold 11 pt monospace capsule 20 pt above the bottom —
  `typeMain` (info), `accent1Main` (success: "Extracted text.", "AutoPasting clipboard...", extension messages),
  `accent4Main` (warning), `accent5Main` (error).

## Saving & analysis

- Edits are debounced 300 ms, then `Services.store.update` saves `content` and `links`. Pending saves flush on
  `load(_:)` and on app termination. Store `.updated` events for the current note reload it when no local edit is
  pending (sync).
- Each change re-runs `Services.analyzer.analyze` (when present) and publishes it through `onAnalysis`.

## Lists ("Toggle Checklist Item", "Indent/Outdent List Line", "Inline list continuity on enter")

- Markers live in the text: `[ ]`, `[x]`, `- `, `* `, `1. ` (after optional indentation). Their characters are
  hidden and take no width, so item text lines up with the body; the checkbox (`typeMain` outline, `accent2Main`
  on hover, `accent2Secondary` at half strength when checked), bullet dot or number is drawn in the gutter.
- `list` notes: "Every line is automatically a new item." Non-empty lines without a marker get `[ ] ` added,
  except `# headers` and `// comments`.
- Click a checkbox to toggle; checked items are struck through in `typeLight`. `Defaults[.checkedItemBehavior]`:
  keep, move to the bottom of the list block ("Moves to the bottom"), or delete.
- Return continues the list (`Defaults[.listContinuity]`, new checkbox unchecked, numbers +1); Return on an
  empty item removes the marker (ends the list). Otherwise Return keeps the previous line's indentation
  (`Defaults[.keepIndentOnReturn]`, "Maintain tab indent on enter").
- Tab / Shift-Tab indent / outdent list lines and multi-line selections ("Tab Highlighted Lines",
  "Untab Highlighted Lines"). ⌘⇧M cycles none → checkbox → bullet → numbered → checkbox. Numbered runs renumber.

## Math & summaries ("Calculated results can't be edited.")

- `LineAnnotation`s draw right after their line's text, on its last wrapped fragment: a space then the result after
  a trailing "=", otherwise " = result" (`EditorLogic.Annotations`). Results are `accent3Main`, errors
  `accent5Main`, info `typeLight`. A result that doesn't fit starts its own row under the line (the row is
  reserved with paragraph spacing). They are not text: not selectable, not copied.
- Math variables: the defined name (`NoteAnalysis.definitions`) in `accent1Secondary`, its colon in `accent2Main`,
  later uses in `accent1Tertiary`.
- Clicking a result copies it ("Copied to clipboard"). With `Defaults[.preventEditingAnswers]` off, ⌥-click
  appends ` = result` text to the line; with it on, ⌥-click shows "Calculated results can't be edited."
- `NoteAnalysis.summary` ("Total: $40") draws as a generated line after a blank line below the note, in
  `accent3Secondary` (sum), `accent4Secondary` (avg) or `accent5Secondary` (count).

## Links ("Shorten long links automatically", "Detect and highlight links")

- With `Defaults[.shortenLinks]`, a pasted URL or a typed URL followed by space/Return is replaced by
  `Services.analyzer.shorten(url:)` and recorded as a `ShortLink`. Short links draw in the link colour, underlined.
- Ranges are tracked in memory (located by searching for `short` at load) and shifted on every storage edit;
  a link whose text no longer matches is dropped.
- Clicking a short link expands it to the full URL for editing; it re-shrinks once the caret leaves.
  "Expand all links" toggles all links expanded. ⌘Return opens the link (short or raw) under the caret.
- Typing inside a short link: "Cannot edit within shortened links. Expand before editing."; an edit overlapping
  only part of it: "Cannot partially edit shortened links. Expand before editing." Deleting a whole link is fine.
- `Defaults[.detectLinks]` underlines raw `http(s)://` URLs too. Copy writes full URLs, never short text.

## Code ("Enables syntax higlighting. Disables paste stripping.", "Pasted as-is in code note")

- `code` notes and ``` fenced blocks: monospaced font, rounded background behind the block, and a small tokenizer
  (strings, comments, numbers, keywords). The language comes from `code <lang>` arguments or is auto-detected
  (Swift, Python, JavaScript/TypeScript, Go, Rust, C-family, Shell, SQL, Ruby, JSON).
- Paste is inserted as-is in code notes and inside fenced blocks.

## Paste & OCR ("Drop an image to capture text.", "Unable to load image. Try copy/pasting.")

- Paste: string → `cleanPaste` (when `Defaults[.cleanPaste]`, not in code) → link shortening → insert.
- An image (pasted or dropped) runs Vision `VNRecognizeTextRequest` (accurate, language correction) and inserts the
  recognised lines. While an image is dragged over the editor an overlay says "Drop an image to capture text."

## AutoPaste ("Enter to start AutoPaste. Everything you copy will be added here.", "Esc stops autopaste")

- In `paste`/`autopaste` notes, Return on the keyword line starts polling `NSPasteboard.changeCount` every 0.4 s;
  each new string (cleaned) is appended as a new line. Esc or leaving the note stops. While listening, a
  clipboard glyph in `accent3Main` blinks in the gutter at the first line; starting shows "AutoPasting clipboard...".

## Extensions ("Extension Autocomplete - Up/Down Arrow, Tab, Enter, Escape")

- Typing `::` shows a completion panel from `Services.extensions.complete(prefix)`; ↑↓ move, Tab/Return accept
  (inserts `::name()` with the caret inside the parentheses when the signature takes arguments), Esc closes.
  The panel (~60% of the window, `background` with a `typeSuperlight` border) lists 28 pt rows: `›` on the
  selected (`typeHyperLight`) row, the command name, its extension in `typeSuperlight`, and an action badge
  ("⇆ replaceLine" accent 1, "↓ insert" accent 3), with a key-hint footer; "No commands found" when empty.
- Return on a line containing `::name(args)` runs it; the `ExtensionEdit` is applied (insert replaces the
  invocation, replaceLine, replaceAll, openURL opens and removes the invocation, message/failure → inline toast).

## Copy & cut ("Copy entire note when nothing is selected", "Removed keyword from copied text.",
"Copied list items as unchecked.", "Removed hidden list markers from copied text.", "Cut current line when nothing is selected")

- ⌘C without a selection copies the whole note (`copyWholeNoteWhenNoSelection`) minus the keyword line
  (`skipKeywordWhenCopying`). All copies expand short links; outside code, `copyListItemsUnchecked` turns `[x]`
  into `[ ]` and `skipListMarkersWhenCopying` drops markers. A toast names what happened.
- ⌘X without a selection cuts the current line (`cutLineWhenNoSelection`).

## Commands (`EditorCommand`)

toggleCheckbox (adds `[ ] ` to a plain line, toggles otherwise), cycleListStyle, indent, outdent, moveLineUp/Down,
duplicateLineUp/Down ("Duplicate Line Up/Down"), strikethrough (toggles `~~text~~` around the selection or line
content — "Strikethrough Text"), find / findAndReplace / findNext / findPrevious (the system find bar via
`NSTextFinder`, which has Ignore Case and Full Word options — "Find and Replace", "Matches Word"),
increase/decrease/resetTextSize, copyAll ("Copied all to clipboard"), selectLine, expandAllLinks,
showExtensionAutocomplete. Each programmatic edit is one undo step.

## Vim ("Modal editing with Normal, Insert, and Visual modes. Press Escape to return to Normal mode.", "Visual Line")

- `Defaults[.vimMode]`: Normal / Insert / Visual / Visual Line with a block caret in Normal and a mode label in
  the bottom-left corner.
- Motions with counts: h j k l w b e 0 $ ^ gg G. Operators: x, d, y, c with motions, dd yy cc, D C, p P (linewise
  aware), o O i a I A, v V (d y c x in visual), u, ctrl-r, `/pattern` then n N, Esc.

## Read-only & locked

- `note.isReadOnly` → not editable (still selectable/copyable). Locked notes are never loaded by the shell.
