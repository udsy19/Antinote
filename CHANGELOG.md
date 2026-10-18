# Changelog

All notable changes to Super Notes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org).

## [1.3.6] — 2026-10-18

### Fixed
- 1.3.5 couldn't start: macOS refused to load the bundled on-device AI engine. This release includes everything
  from 1.3.5 (on-device AI commands, typing options, tidier corner buttons) and starts normally. If you have 1.3.5,
  reinstall from the website or the DMG once.

## [1.3.5] — 2026-10-18

### Added
- AI commands work out of the box: `::ask`, `::summarize`, `::rewrite` and `::translate` are answered on your Mac
  by a small open model (Qwen3.5 2B, Q4_K_M, Apache-2.0, 1.28 GB) run with llama.cpp. Super Notes fetches it once
  in the background a few minutes after launch — only on Wi-Fi or another unmetered connection, never in Low Power
  Mode, only with 10 GB free, at low priority, resumed where it stopped and verified against its SHA-256 before it
  is used. A command used before the model has arrived shows "Getting ready… 40%" in the note and runs on its own
  when it has; when the download can't run it says so ("Try again when the download finishes"). Esc stops an answer
  that is being written. The pill wraps and never widens the window.
- Settings → AI: the engine (On-device model, Apple on-device model on macOS 26 — chosen for you where the Mac has
  it — or an installed command-line tool), the model's state with size and progress, Download Now / Pause /
  Remove / Re-download, and "Download models automatically" (on by default; also listed in Settings → Privacy with
  its host, `huggingface.co`).
- An optional engine that runs a command-line tool you installed and signed in to yourself (`codex`, `claude` or
  `gemini`, found on your PATH or in the usual install folders) as a separate program in its non-interactive mode,
  with a timeout; only when you pick it, labelled plainly with the tool's name. Super Notes never reads its sign-in.
- Extensions can ask the chosen engine with `AI.complete(prompt, {system, maxTokens})` by declaring
  `"usesAI": true` in their manifest; the permissions list says so.
- The bundle embeds llama.cpp's framework in Contents/Frameworks, signed before the app that seals it.

- A Typing button in the top bar (the “A” after Settings and Search; tooltip "Typing options"): a menu of
  checkmarks that take effect at once in every note and stay set — Check Spelling While Typing, Correct Spelling
  Automatically, Check Grammar, Capitalize Words Automatically, Smart Quotes, Smart Dashes, Text Replacements. Only
  spelling is on to begin with (a scratchpad shouldn't rewrite what you type). Code notes are never checked; code
  and math notes get no substitutions or capitalisation, and the menu says so under the items. The same switches,
  with the same names, are in Settings → Editor → Typing, and the note's right-click Spelling / Substitutions
  toggles write the same settings. Capitalisation is Super Notes' own: the first word of a line or sentence is
  capitalised once it's finished, never URLs, paths, addresses, "example.com", "e.g." or words spelled with
  capitals of their own ("iPhone"). The settings sync with the rest.

### Fixed
- Search no longer fights the window's bottom bar: resting the pointer along the bottom of the Search view brought
  Delete / Previous / Next / Latest / Export up over Search's own Select | Ephemeral and list / cards capsules (and
  their tooltips over each other). A mode that brings its own bottom controls — Search, the find shelf — now owns
  the bottom strip: the bottom bar, the slot bar and the latest-note dot stay down until it closes. Search's
  capsules sit where the bar's buttons would be (10 pt in, centred 20 pt up, 30 pt tall); under 261 pt the Typing
  button gives way, and in a narrow Search the Select and Ephemeral items keep their glyphs and drop their labels,
  so nothing overlaps at any width from 240 pt up (a self-test checks every mode at 240, 350, 600 and 1200 pt).
- The corner buttons share one size system (`ChromeMetrics`): 30 pt buttons with 22 pt glyphs, rows centred 20 pt
  from the top and bottom edges (the traffic lights on the same row), 10 pt from the sides, 8 pt apart in both
  bars (the top bar's buttons used to touch). Every button has the same hover and pressed shape, a disabled state,
  a keyboard focus ring with Full Keyboard Access (Space or Return presses it) and an accessibility label.

### Removed
- The AI commands' provider list (OpenAI, Anthropic, Gemini, OpenRouter, Ollama), their API keys and their HTTP
  calls. "Let extensions call their own APIs" stays for community extensions that need the network; the built-in
  AI commands no longer need it.

## [1.3.4] — 2026-10-18

### Added
- `::` commands say what goes in the parentheses: while the caret is inside `::today(…)`, a small hint above it
  shows `::today(days = 0, format)` with the argument being typed in bold and one line about it ("days — how many
  days from today, e.g. 3 or -1 (default 0)"). Commands that take nothing say "Press Return to run"; when every
  argument is optional, "Press Return to use the defaults, or type to change them". It follows the caret, never
  takes the keyboard or the mouse, and Esc closes it. Every bundled command documents its arguments.
- Picking a command from the `::` list puts the caret between its parentheses, and Return there runs it (a missing
  closing parenthesis is filled in); typing `)` before the closing one steps over it. Extensions can give each
  parameter an `example`.

### Fixed
- A long message can no longer make the note window wider: running `::ask` without network access showed its error
  on one line and stretched the window to fit it. Message pills now wrap at the note's text column to at most three
  lines (the whole message is in the pill's tooltip), and only you resize the window. The message itself is shorter:
  "Turn on “Let extensions call their own APIs” in Settings → Privacy."
- The planets bar stays out of the way while writing: it is hidden by default and comes up only once the pointer
  has rested along the bottom of the window for a moment, for two seconds after a slot is used, or with "Always
  show the slot bar" — and a keystroke takes it down in every case, until the pointer comes back or typing has
  stopped for two seconds. It floats over the note, so the text never moves. (Before, it rose with the bottom bar
  whenever the pointer drifted low and sat over the last lines being typed.)
- Moving between slots is predictable: your notes are the deck, the nine slots are pinned notes. Opening a slot
  fades its note in and names it above its planet ("Slot 3 · Groceries"); Esc, ⌃⌘0 or Back to Notes returns to
  the note you left, caret and scroll position intact. Swiping or ⌘[ / ⌘] in a slot moves through the slots in
  use only, in order, and nudges back at the ends ("First slot" / "Last slot") instead of jumping into empty slots
  or the deck; nothing is ever created from a slot. In the split, swipes follow the pane that has the focus.
- Slot shortcuts are always on and in the menu: Go to Slot 1…9 ⌃⌘1…⌃⌘9, Previous / Next Slot ⌃⌘[ / ⌃⌘],
  Back to Notes ⌃⌘0, Put in Slot ⌥⌘1…⌥⌘9. The "⌘1–⌘9 jump to slotted notes" switch drops the ⌃. The planet
  tip shows each slot's shortcut, how to get back from the open one and how to fill an empty one.
- Putting a note in a slot keeps its caret; replacing an occupied slot or removing a note from its slot happens
  at once with a pill that says what ⌘Z puts back (Undo Move to Slot), instead of a question. Right-clicking a
  planet offers Open, Put This Note in, and Remove from that slot.

## [1.3.3] — 2026-10-18

### Fixed
- Undo and redo work: ⌘Z undoes, ⇧⌘Z and ⌘Y redo, in the note and in every text field. Typing undoes a word at a
  time; checking off an item, moving or duplicating a line, indenting, pasting, cutting, shortening a link,
  running a `::` command or a "/" command each undo as one step that puts the text and the selection back, and
  the Edit menu names them ("Undo Paste"). Each note keeps its own history for the session, saving never clears
  it, Vim's `u` and ⌃R use the same history, and ⌘Z right after deleting a note brings it back from The Void.
  (Before, the text view's own undo lost track as soon as the editor rewrote a list marker or shortened a link
  inside a keystroke, and then stopped working.)
- Nothing in the way while writing: the hover bars drop as soon as you type, a message pill moves to the top when
  the caret is low, and a finished timer's alert no longer takes the keyboard away from whatever you were typing.
- One word for one thing: deleting is "Delete" in the menu, the palette, the pills and the confirmation; moving a
  note to the front is "Move to Front"; The Void labels its Restore buttons and says "Deleted 3 hours ago". Pills
  say what to do next ("Click the link to expand it before editing"). The duplicate Support menu is gone (Help has
  its items), and two Appearance toggles say what they do.

## [1.3.2] — 2026-10-18

### Fixed
- The "/" list and the `::` list work with the mouse: the row under the pointer is selected, a click runs it, the
  scroll wheel scrolls longer lists, and clicking elsewhere closes them, all without taking the caret away from the
  note. Both now share one tidier popover: keyword chips in their colours, aligned descriptions, numbers on the right.
- The slot bar's planets are drawn crisply above its glass instead of blurred under it. Slots holding a note are
  filled, empty ones outlined, and hovering a planet shows which note it holds or how to fill it. Moving from the
  bottom bar onto the slot bar no longer hides it, and an always-shown slot bar no longer covers the end of a note.
- The bottom bar never runs past the window edge: the date is shortened, then hidden, then Export and First make
  room in narrow windows. The find shelf no longer forces the window's content wider than the window.

## [1.3.1] — 2026-10-18

### Changed
- Maintenance release; the first update delivered through automatic background updates.

## [1.3.0] — 2026-10-17

### Added
- In-app updates: Super Notes checks GitHub Releases in the background, downloads a newer version, verifies its
  SHA-256 and code signature, and installs it when you quit, or while your Mac sits idle by reopening unseen.
  "Updated to …" shows once afterwards. Settings → Updates shows when it last checked, and Settings → Privacy →
  Install updates automatically turns it off.
- The welcome note teaches the global shortcut and says that notes stay on this Mac; reaching the last tutorial
  note shows "The tutorial is over".

### Changed
- New minimal app icon: three ink lines on a white squircle. The menu bar glyph matches, and the alternate icons
  are now Light, Dark, Paper and Sage colourways of it.
- New website.

## [1.2.0] — 2026-10-17

### Changed
- Renamed to Super Notes (bundle id com.udsy.supernotes, URL scheme supernotes://). Notes, settings and keys move
  over automatically.

## [1.1.0] — 2026-10-17

### Added
- "/" palette: type "/" at the start of a line (or after a space) for keywords and commands; digits pick, letters
  filter, "//" or Esc closes it.
- Every menu shortcut can be rebound in Settings → Shortcuts, with conflict checks and per-row reset.
- A find-and-replace bar with match case and Contains / Matches Word / Starts With / Ends With / Regex modes.
- Five more themes: Meadow, Armor, Stealth, Spice and Bubblegum.
- Settings: start with a new note, drop-down window size, solid bars and translucency opacity, a separate theme
  for slotted notes, spell check, Vim motion timeout, per-marker automatic lists, auto-copy, caret offsets,
  "Check off items with" (`/x`), separate timer alert sounds with volume, first-line titles and custom URL export.

### Changed
- The look follows Antinote closely: theme colours, text sizes and spacing, list markers, a 350 × 400 window,
  30 pt top-bar buttons, the "date | N of M" bottom bar, menus and an 800 × 500 Settings window.
- Two-finger swipes switch notes as soon as the gesture starts, one note per flick.
- Math results show a fixed number of decimal places (2 by default) without the primary currency symbol.
- ⌘F opens Search All Notes and ⌘D deletes the note; ⌘1–⌘9 for slots is off by default.
- "Default list style" now applies to new list items.

## [1.0.0] — 2026-10-17

First public release.

### Added
- A scratchpad window on a global hotkey (⌥A by default), shown from the Dock, the menu bar, a drop-down
  "pseudo menu bar", or the hotkey alone.
- A deck of notes: swipe with two fingers or press ⌘[ / ⌘] to move through it, past the newest note to start a
  fresh one. Empty notes clean themselves up.
- Nine slotted notes (⌘1…⌘9) that stay put while the deck moves on, with an optional split view.
- First-line keywords: `list`/`todo` checklists, `math` with units, currencies, crypto, percentages and variables,
  `sum`, `avg` and `count`, `timer` (countdown, stopwatch, pomodoro, breathe), `code` with syntax highlighting, and
  `paste` (AutoPaste collects everything you copy).
- `::` extensions in JavaScript: date, lines, text, random, json, regex, finance, checklists, templates and `llm`
  (OpenAI, Anthropic, Gemini, OpenRouter or a local Ollama model, with your own key). Install more from GitHub.
- Command palette (⌘K), Search All Notes (⇧⌘F), find & replace, Vim mode.
- The Void: deleted notes stay recoverable for a retention period you choose. Daily automatic backups.
- Lock notes behind Touch ID or your password; read-only and archived notes.
- Export to Apple Notes, Obsidian, Bear, Markdown, plain text and PDF; Quick Export (⇧⌘E); export all notes.
- Optional end-to-end encrypted sync through your iCloud Drive folder.
- Built-in light and dark themes plus custom theme files, lined, dotted or grid paper, a translucent window on
  macOS 15+ and alternative app icons.
- A `jotter://` URL scheme for Shortcuts, Raycast, Alfred and the shell.
- Settings → Privacy: every network feature has its own switch, plus Turn Everything Off.
- One-line installer and a universal (Apple silicon + Intel) DMG.

[1.0.0]: https://github.com/udsy19/super-notes/releases/tag/v1.0.0
