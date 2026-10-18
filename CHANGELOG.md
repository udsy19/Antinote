# Changelog

All notable changes to Super Notes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org).

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
