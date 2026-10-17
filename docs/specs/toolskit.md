# ToolsKit

Timers & pomodoro, export, the `jotter://` URL scheme, the command palette, The Void window and Search All Notes.
Implements `TimerServicing`, `ExportServicing` and `PanelServicing` from JotterCore and installs the URL-scheme
Apple-event handler. Depends only on JotterCore; everything else is reached through `Services`.

## What Antinote does (evidence)

Sources: the class digest (`TimerManager`, `TimerPreferences`, `TimerCompleteAlertController`, `ExportManager`,
`ExportPreferences`, `PrintManager`, `URLSchemeManager`, `SearchField.Coordinator`, `NotesManagement`) and UI strings.

- **Timers.** A `timer` note's first line drives `TimerManager` (`_startTime`, `_breakTime`, `_timeLeft`,
  `_cycleCount`, `_isPaused`, `_timerType`, `_timerTitle`, `_isWorkPhase`, `timerStateTimestamp`). The built-in help:
  "Enter to start a stopwatch." / "timer 5 - to countdown" / "timer 5:30 : laundry - to name a countdown" /
  "timer pomo - to start a 25m/5m pomodoro." / "timer 52 17 - will run a custom pomodoro of 52mins/17mins" /
  "timer p - pause/resume" / "timer r - reset" / "timer s - stop" / "timer breathe - to chill" / "Click to pause" /
  "Double-click to stop". Parser regex: `(?:pomo|pomodoro|breath|breathe|p|r|s)`.
  Messages: "Stopwatch started", "Countdown started", "25/5 Pomodoro started", "Cannot countdown zero minutes",
  "Cannot start countdown at 0", "Pomodoro start time and break time cannot be zero", "Timer only accepts 2 numbers.",
  "Unable to parse timer command.", "Your countdown timer is over.", "Work Session Complete",
  "Break time remaining:", "Next work session started.", "Breathe in.", "Breathe outtttttt.", "Breathing started".
- **Timer preferences** (`TimerPreferences`): "Show a full-screen alert", "Show a notification" (separately for
  countdowns and pomodoros), sound + volume ("Affects both countdown and pomodoro alert sounds."), "Show time left in
  the menu bar" (`statusItem`), "Pause timer when quitting the app" (`_pauseTheTimerIfAppClosed`), "Esc closes timer
  alert overlay". The completion overlay shows a random encouraging line (Antinote uses animal facts; Jotter writes
  its own short messages instead).
- **Export** (`ExportPreferences`): Plain text, Markdown, Bear (`bear://x-callback-url/create`), Obsidian (vault
  name, convert to Markdown), Apple Notes (originally via the "Apple Notes helper Shortcut"), a custom URL scheme
  ("Send notes to any app that accepts a URL scheme."), "Omit keyword in exported notes", "Quick Export in the File
  menu sends the current note straight to this destination.", "Export all notes", "Note is too long. Export to txt,
  md, or copy/paste.", "No note to export". `PrintManager`: `handlePrintNote`, `handleExportPDF`, "Failed to export PDF".
- **URL scheme** (`URLSchemeManager`: `isAppReadyForURLSchemeHandling`, `pendingURLs`, `actions`): `createNote`,
  "append to current note", "overwrite current note", `togglepin`, "promote and open", "refresh db". URLs arriving
  before the app is ready are queued.
- **Command palette**: "Show Command Palette", "Search extensions, commands, or descriptions...", "Esc closes command
  palette", "Choose command palette quick option", "Double slash makes a comment while palette is open".
- **The Void**: "Deleted notes will drift here", "Recover them, or erase them permanently.", "Delete from The Void?",
  "There is no recovery beyond The Void.", "The Void is empty", "The Void is already empty", "Restore from The Void".
- **Search**: "Search All Notes", "Try a different search term", "Clear the search to rearrange notes".

## How Jotter implements it

### Timers (`TimerSpec`, `TimerRun`, `TimerManager`, `TimerOverlay`)
- `TimerSpec.parse(_:)` (pure) turns the first-line arguments into a command. The keyword itself may be passed in
  front ("pomodoro 25 5", "countdown 5m"); when the editor passes only the arguments, the manager re-reads the note's
  first line through `NoteMode.detect` to recover `stopwatch` / `countdown` / `pomodoro` keywords.

  | Arguments | Result |
  |---|---|
  | `` / `stopwatch` | stopwatch |
  | `5`, `25m`, `90s`, `1h30m`, `1h 30m`, `10:00` (m:ss), `1:30:00` (h:mm:ss), `countdown 5m` | countdown |
  | `pomo`, `pomodoro` | pomodoro with `Defaults[.pomodoroWorkMinutes]` / `[.pomodoroBreakMinutes]` |
  | `52 17`, `pomodoro 52 17`, `pomo 50m 10m` | custom pomodoro |
  | `breathe`, `breath` | breathing exercise (4 s in, 6 s out) with the animated circle overlay |
  | `p` / `pause`, `r` / `reset`, `s` / `stop` | control the note's running timer |
  | trailing words or `: name` (`5m tea`, `5:30 : laundry`) | timer name |

  Errors: "Cannot countdown zero minutes", "Pomodoro start time and break time cannot be zero",
  "Timer only accepts 2 numbers.", "Unable to parse timer command." (shown as a HUD).
- `TimerRun` (pure, Codable) is the state machine: accumulated time + the start of the current running segment, so
  every query takes an explicit `now` (tests inject a clock). Pomodoro phases are derived from elapsed time
  (`phaseIndex = 2·cycle + (inBreak ? 1 : 0)`); `events(from:to:)` reports `finished`, `workEnded(n)`, `breakEnded(n)`.
- `TimerManager` keeps one timer per note (any number of notes, each with an optional name), ticks once a second while
  any timer runs, and posts `Notification.Name("JotterTimersDidChange")` (object: note UUID) so the editor can refresh
  `status(noteID:)`, e.g. `24:59 · work 1 · tea`, `03:12 · paused`, `Done · tea`.
  `start` on a running timer with the same spec resumes it instead of restarting. Public extras: `pause`, `resume`,
  `reset`, `togglePause`, `runningNoteIDs`, `showFullScreen(noteID:)`.
- Menu bar (`Defaults[.timerInMenuBar]`): one `NSStatusItem` titled with the soonest-ending timer (stopwatches only when
  nothing counts down); its menu lists every timer with pause/resume, full screen, open note and stop.
- Completion (`Defaults[.timerAlertStyle]`): `fullScreen` → a borderless overlay on the active screen with a big title,
  an original encouraging line, Dismiss (Esc) and a "Breathe" button that switches to an animated breathing circle;
  `notification` → `UNUserNotificationCenter` (only when running from an app bundle); `both`. Pomodoro transitions
  ("Work Session Complete" + "Break time remaining:", "Next work session started.") use the same channels.
  Sounds (`Defaults[.timerSounds]`): system sounds "Glass" (done), "Hero" (break), "Ping" (work).
- Persistence: every state change is saved under the module key `toolsKit.timers`. On quit, with
  `Defaults[.pauseTimersOnQuit]` running timers are paused and flagged; on launch flagged timers resume. Without the
  setting timers keep counting in wall-clock time and anything that ended while the app was closed is marked done.
- Full-screen view of a running timer: the same overlay showing the live clock, phase and name.

### Export (`ExportManager`, `ExportText`)
- `ExportText` (pure): optional keyword removal (`Defaults[.omitKeywordInExport]`; the first line is dropped when
  `NoteMode.detect` recognises it), title = first remaining line, Markdown conversion: `☐ ◻ □ [ ]` → `- [ ]`,
  `☑ ☒ ✓ ✔ [x]` → `- [x]`, `• ◦ ‣ ▪` → `-`; in list-mode notes unmarked lines become `- [ ]`. Indentation is kept.
- Apple Notes: `NSAppleScript` `tell application "Notes" to make new note with properties {name:…, body:…}` (HTML
  body). Error -1743 explains how to allow Automation (System Settings → Privacy & Security → Automation).
- Obsidian: `obsidian://new?vault=<Defaults[.obsidianVault]>&name=&content=` (vault omitted when empty).
  Bear: `bear://x-callback-url/create?title=&text=`. URLs longer than 60 000 characters are refused with
  "Note is too long. Export to txt, md, or copy/paste."
- Plain text / Markdown: `NSSavePanel` named after the title. PDF: an `NSTextView` laid out with the editor font
  (`Defaults[.fontName]`/`[.fontSize]`, theme text colour forced to black on white paper) printed to file via
  `NSPrintOperation` (`jobDisposition = .save`). `print(_:)` shows the print panel.
- `exportAll(to:)` writes every deck and archived note as `<title>.md` (unique names, Markdown conversion applied)
  plus `Jotter Notes.json` from `Services.store.exportJSON()` (re-importable, keeps slots/links/dates).

### URL scheme (`URLCommand`, `URLSchemeHandler`)
`kAEGetURL` is handled from `ToolsKitModule.install()`; URLs arriving before `Services.store`/`windows` exist are queued
and replayed after `didFinishLaunching`. Commands (host of the URL, parameters percent-decoded):

| URL | Action |
|---|---|
| `jotter://new?text=…` | create a note at the front and show it |
| `jotter://append?text=…` | append a line to the current note (creates one when there is none) |
| `jotter://overwrite?text=…` | replace the current note's text |
| `jotter://show?id=<uuid>` | show that note |
| `jotter://promote?id=<uuid>` | move to the front and show (slotted notes cannot be promoted) |
| `jotter://togglepin` | toggle `Defaults[.pinOnTop]` |
| `jotter://palette`, `jotter://search?q=…`, `jotter://void` | open the panels |

Shell use: `open "jotter://append?text=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "milk")"`.

### Command palette (`CommandPalette`, `FuzzyMatcher`, `QuickPanel`)
- `QuickPanel`: floating non-activating-style `NSPanel` (search field + table), ↑/↓ move, Enter runs, Esc or focus
  loss closes; shared by the palette and search.
- Items: new note, go to note (deck titles), slots, export to each enabled destination, export all, print, toggle pin,
  settings tabs, timer presets and running-timer controls, insert keyword (sets the current note's first line), extension
  commands from `Services.extensions.commands` (appended as `::name()`), The Void, Search All Notes.
- `FuzzyMatcher.score` (pure): case-insensitive subsequence match; bonuses for exact/prefix match, word starts and
  consecutive characters, penalties for gaps and late starts. Ties keep the item order. Empty query lists actions.

### The Void (`VoidWindowController`)
SwiftUI list of `Services.store.void` (two-line preview, "Deleted <relative date>"), Recover, Delete (confirm
"Delete from The Void?" / "There is no recovery beyond The Void."), Empty The Void, retention footer from
`Defaults[.voidRetentionDays]`; empty state "Deleted notes will drift here" / "Recover them, or erase them permanently.".
Refreshes on `Services.store.changes`.

### Search All Notes
`QuickPanel` fed by `Services.store.search(q, includeArchived: true)`; each row shows the title and a snippet around the
first hit with every match highlighted (`SearchSnippet`, pure). Enter → `Services.windows.show(noteID:)`.
Empty results: "Try a different search term".

## Gaps / requests
- Core: a timer-change publisher in `TimerServicing`, `pause/reset` in the protocol, `print` in `ExportServicing`,
  a shared settings-tab enum, an editor-insertion hook in `WindowServicing`; the app's Info.plist needs
  `CFBundleURLTypes` (`jotter`) and `NSAppleEventsUsageDescription`.
- Not implemented: Notion and custom URL-template export, the "refresh db" URL command.
