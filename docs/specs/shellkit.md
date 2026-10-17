# ShellKit — window, deck, slots, presence, menus, settings

ShellKit owns everything around the editor: the main note window and how it appears, deck navigation,
slotted notes, the main menu, locking, the Settings window, onboarding notes and app icons. It registers
`Services.windows` and talks to other modules only through `Services`.

Evidence below refers to the reference app (class names and UI strings from its binary and `Localizable.strings`).

## Main window

Evidence: `WindowManagement` (mainWindow, popoverWindow, settingsWindow, mainWindowDelegate,
themeAppearanceObserver), `WindowTopBar` (buttonVisibilityState, isHovered), `CustomTitleBarView`
(settings/new/search/pin buttons, mouseEntered/mouseExited), `WindowButtonCustomizer`, strings
"Or mouse over the top part of Antinote to click cool sci-fi buttons", "Make Antinote translucent",
"Requires macOS 15 (Sequoia) or later.", "Translucency opacity".

- A small (default 380×440) titled window with a transparent, full-size title bar; the title is hidden.
- The top strip (28 pt) is a custom title bar. Its buttons — New Note, Split View (slots), Pin, Settings,
  More (…) — and the traffic lights fade in while the pointer is over the strip and fade out on exit.
- Below it: the optional slots bar, the editor area (one pane or a split), and a bottom bar.
- Bottom bar: mode summary on the left; on the right the optional date, the position "3 / 12" and the
  latest-note dot ("Marks the most recent note on the bottom right" → `showLatestNoteIndicator`).
  Clicking the position jumps to the front note.
- The editor comes from `Services.editorFactory.makeEditor()`; each pane owns one editor.
- Background = `Theme.current.background`; re-applied on appearance change, `Theme.didChange` and theme keys.
- Translucent (`translucent`, macOS 15+ only): a behind-window visual-effect view under a theme tint.
- Frame is autosaved (`setFrameAutosaveName`) in normal presence modes.
- Closing the window hides it (the app keeps running); ⌘Q quits.

## Deck navigation

Evidence: `SwipeGestureDetector.Coordinator` (local event monitor), `NotesManagement` (_currentIndex,
previouslyViewedIndex, deletedNotes), strings "Swipe between notes", "Swipe horizontally on the trackpad to
move to the previous or next note.", "Swipe sensitivity", "Higher values require more deliberate swipes.",
"Empty note deleted", "Jumped to latest", "Note is already first", "Create a new note after",
"Start with a new note", "Use latest empty note", tutorial "[←] Swipe or ⌘+[ to see the previous note."

- The deck is `Services.store.deck` minus slotted notes, front (newest) first. Index 0 = latest.
- Previous (older) = index + 1: two-finger swipe with fingers moving right, or ⌘[. Next (newer) = index − 1:
  fingers moving left, or ⌘].
- Moving newer from the front note creates a new note — unless the front note is empty ("Already at latest").
  Moving older from the last note does nothing.
- Leaving a note whose text is blank deletes it (`NoteStoring.deleteIfEmpty`, not to The Void) and shows "Empty note deleted";
  slotted notes are never auto-deleted.
- Swipe recognition (`SwipeAccumulator`): only phased (trackpad) scroll events; the gesture locks to the
  horizontal axis when |dx| > 1.5·|dy| after 6 pt of travel; it fires once per gesture when |Σdx| reaches
  `30 + 170·swipeSensitivity` points. Momentum events of a horizontal gesture are swallowed.
- `swipeNavigation` off disables swipes (⌘[ / ⌘] keep working).
- Inactivity (`newNoteAfterMinutes`, 0 = never): when the window is shown after being hidden at least that
  long, Jotter shows the front note if it is empty, otherwise creates a new note.
- Go to First Note (⇧⌘L) jumps to the front.
- The current note ID survives relaunches (`shellKitCurrentNote`).

## Slots

Evidence: `NotesPreferences` (_slotedNotesLimit, _alwaysShowSlottedBar, _lastActiveSlottedNote, _isSplitView,
_storedIsSlottedMain, _createNewNoteInEphemeralFromSlotted, _isSplitHorizontal), `TextViewRegistry`
(mainTextView, slottedTextView), strings "This is your first of nine slotted notes", "Always show the slotted
notes bar", "Create new notes in the ephemeral pane when in slotted view", "Swap Ephemeral vs. Slotted",
"Split horizontally", "Toggle Split Screen", "Slot not available", "Opened slotted note",
"No slotted notes yet", "⌘1…9 jump to slotted notes", "New notes can only be created in the ephemeral pane".

- Nine slots (`Note.slot` 0…8). Rules (`SlotBoard`): assigning a note to its own slot removes it from the slot;
  assigning to an occupied slot pushes the occupant back to the deck; a note is in at most one slot.
- ⌘1…⌘9 open slots; ⌘0 returns to the ephemeral deck. ⌃⌘1…⌃⌘9 assign the current note.
- The slots bar (numbered chips, ∞ chip for the deck) shows when `alwaysShowSlotsBar`, when any slot is used,
  or while a slot is open. Clicking an empty chip assigns the current note to it.
- Split view (`shellKitSplit`): ephemeral pane + slotted pane, side by side or stacked
  (`shellKitSplitHorizontal`, "Split horizontally"), order swappable (`shellKitSwapPanes`).
- ⌘N while a slotted note is focused creates the note in the ephemeral deck when
  `shellKitNewNotesInEphemeral` is on (default), otherwise shows a HUD.

## Presence

Evidence: `StatusItemManager` (statusItem, handleClick, showHideMainWindow, createNewNote), `PinStateManager`,
`HotKeyManager`, `StartupManager`, strings "Show Antinote in", "Dock and Pseudo Menu Bar", "Pseudo Menu Bar -
app will hide/show when you click the menu bar", "Nothing - Can only be accessed via the Global Hotkey
shortcut, Spotlight, or equivalent", "Hide Antinote when it loses focus", "Applies only while the window is
unpinned.", "Restore pin state on open", "Launch Antinote at login", "Pin Antinote to Top", "Unpinned from top".

| `appPresence` | Dock icon | Status item | Status item click |
|---|---|---|---|
| dock | yes | no | — |
| menuBar | no | yes | toggle window |
| dockAndMenuBar | yes | yes | toggle window |
| pseudoMenuBar | no | yes | window drops down under the item; any click outside hides it |
| hidden | no | no | — (global hotkey, Spotlight, reopen) |

- Changes apply live (activation policy + status item). Right-click on the item: New Note, Settings, Quit.
- Global hotkey `globalHotkey` (default ⌥A) via `HotkeyCenter` toggles the window; re-registered on change.
- Pin on top (`pinOnTop`) = floating level; reset at launch unless `restorePinState`.
- Hide on focus loss (`hideOnFocusLoss`) only while unpinned; always in pseudo-menu-bar mode.
- Launch at login: `SMAppService.mainApp` register/unregister when `launchAtLogin` changes.
- Reopening the app (Dock click, Spotlight, `open`) shows the window (kAEReopenApplication handler).

## Menus

The menu table (`MenuCatalog`) is the single source for the menu bar and the Settings → Shortcuts list.
App: About, Settings… ⌘,, Hide ⌘H, Hide Others ⌥⌘H, Show All, Quit ⌘Q.
File: New Note ⌘N, Move to The Void ⌘⌫, Recover from The Void… ⇧⌘⌫, Export ▸ (enabled destinations),
Quick Export ⇧⌘E, Print ⌘P, Close Window ⌘W.
Edit: Undo/Redo, Cut/Copy/Paste, Select All, Copy All ⌥⌘C, Select Line ⌘L, Find ⌘F, Find & Replace ⌥⌘F,
Find Next ⌘G, Find Previous ⇧⌘G, Expand All Links, Extension Autocomplete ⌃Space.
Note: Toggle Checklist Item ⇧⌘M, Cycle List Style ⌃⇧⌘M, Indent ⌥⌘], Outdent ⌥⌘[, Move Line Up/Down ⌥⌘↑/↓,
Duplicate Line Up/Down ⇧⌥⌘↑/↓, Strikethrough ⇧⌘X, Promote to Front ⇧⌘T, Assign to Slot ▸ (⌃⌘1…9,
Remove from Slot), Lock/Unlock ⌃⌘L, Read-Only ⇧⌘R, Archive ⇧⌘A.
View: Increase/Decrease/Reset Text Size ⌘= ⌘− ⌥⌘0, Pin on Top ⇧⌘P, Always Show Slots Bar, Split View ⌃⌘S,
Split Horizontally, Swap Panes.
Go: Previous Note ⌘[, Next Note ⌘], First Note ⇧⌘L, Ephemeral Notes ⌘0, Slot 1…9 ⌘1…⌘9,
Search All Notes ⇧⌘F, Command Palette ⌘K.
Window: Minimize ⌘M, Zoom, Bring All to Front. Help: Show Tutorial Notes, Keyboard Shortcuts.

## Locked notes

Evidence: `PrivateNotesSession` (_revision, lastPrivateFocus, authInFlight), `NotesPreferences`
(_privateRelockMinutesStorage), strings "Require Touch ID or password again after", "Counted from the last
time a locked note was in focus. Quitting Antinote always locks them.", "Relock locked notes",
"Locked notes are locked again".

- Lock: sets `Note.isLocked` (no auth). Unlock (remove the lock) and viewing require LocalAuthentication
  `.deviceOwnerAuthentication` (Touch ID or password).
- A locked, not-yet-authenticated note shows a lock screen (icon, title, Unlock button) instead of the editor.
- `RelockSession`: unlocked IDs are session-only; the clock restarts whenever a locked note is in focus;
  once `relockAfterMinutes` pass without focus (0 = as soon as you leave), all are locked again.
  Settings → Privacy has "Relock locked notes" (immediately).

## Settings window

Evidence: `SettingsTabRouter` (_selected), the *Preferences classes, strings listed per row.
SwiftUI sidebar window; `showSettings(tab:)` routes ids/aliases (`SettingsTab(routing:)`, e.g. "advanced",
"notes", "backups" → Storage; "keyboard", "hotkey" → Shortcuts).

1. General — Show Jotter in; Global hotkey; Launch at login; Restore pin state on open; Hide when it loses
   focus; Create a new note after (never/5/15/30/60/120/480 min); Swipe between notes; Swipe sensitivity;
   Show latest-note indicator; Show note dates; Always show the slots bar; New notes in the ephemeral pane;
   Split horizontally; Force right-to-left layout.
2. Appearance — Light theme / Dark theme swatch grids (Theme.all previews); Paper type; Paper opacity
   (disabled for blank, "Select a non-blank paper type…"); Font; Size; Line spacing; Translucent (macOS 15);
   App icon (drawn variants + "An image of your own").
3. Writing — Vim mode; Keep indentation on Return; Allow macOS text replacements; Detect links; Shorten links.
4. Lists — Default list style; When an item is checked; List continuity on Return.
5. Math — Primary / secondary currency; Significant digits; Update rates daily; Prevent editing answers;
   Custom currency rates editor.
6. Copy & Paste — Clean up pasted text + markdown/bullets/numbering/leading whitespace/empty lines; Copy whole
   note when nothing selected; Cut line when nothing selected; Skip keyword; Copy items unchecked; Skip markers.
7. Keywords — one row per mode: built-in keywords + editable extra keywords (comma separated).
8. Timers — Alert style; Sounds; Time in menu bar; Pause on quit; Pomodoro work / break minutes.
9. Shortcuts — global hotkey recorder; every menu shortcut (read-only list from `MenuCatalog`).
10. Extensions — `Services.extensions.makeSettingsView()` embedded; enable + logging toggles.
11. Privacy — currency rates, extension updates, extension APIs, note/pref/extension sync — each with what it
    calls; Turn Everything Off; relock minutes; Relock now.
12. Sync — three toggles, live `Services.sync.statusText`, Sync Now; Copy Encryption Key / Paste Key from Another Mac
    (`exportKey` / `importKey`).
13. Storage — Void retention; Backups to keep; Make backup now; Restore from backup; Open backups folder;
    Export all notes; Export as JSON / Import JSON (`exportJSON` / `importJSON`); Reset preferences; Reset app to factory settings (destructive confirmation).
14. Export — enabled destinations; Quick Export destination; Omit keyword; Obsidian vault.
15. About — version, MIT license, tutorial button.

## Onboarding & icons

Evidence: `TutorialPreferences` (_showOnboarding), tutorial notes (welcome, math, sum/avg, count, timer, `/`
palette, slotted "first of nine"), `AppIconManager` (_style, _customIcon, applyIcon), strings
"Choose an image to use as the Antinote app icon", "The current Antinote icon.", "An image of your own.",
"App icon updated".

- First launch with an empty deck: seed short tutorial notes (own wording) demonstrating swiping, list, math,
  sum, count, timer, code, paste and `::today`, plus one slotted note; set `onboardingCompleted`.
- App icons are drawn in code (`AppIconArt`): default, midnight, mint, sunset; "custom" uses a chosen image
  copied to `support/AppIcon.png`. Applied with `NSApp.applicationIconImage` at launch and on change.

## Module-private defaults

`shellKitCurrentNote`, `shellKitLastHidden`, `shellKitSplit`, `shellKitSplitHorizontal`, `shellKitSwapPanes`,
`shellKitNewNotesInEphemeral`.
