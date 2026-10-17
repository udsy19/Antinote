# Changelog

All notable changes to Jotter are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org).

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

[1.0.0]: https://github.com/udsy19/Antinote/releases/tag/v1.0.0
