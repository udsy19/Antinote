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

- A small (default 337×386) titled window with a transparent, full-size title bar; the title is hidden. The note
  fills the window and the bars float over it (see ui-reference.md §1).
- Top bar (34 pt, hover): the traffic lights (centred 17 pt down), Settings and Search on the left, New Note and
  Pin on the right — line-art glyphs drawn in code (`ChromeIcon`), `typeHyperLight` hover, `typeLight` pressed,
  `accent3Main` when pinned. The strip drags the window even while hidden.
- Bottom bar (30 pt, hover; gone with "Show bottom bar" off): Move to The Void on the left; the note's date
  ("Show note modified/created time" adds the time, "Show the note creation date" shows when it was created instead of
  last changed) and position "14 of 18" ("Show note count") in the middle; Previous, Next, Latest and Export (a menu
  of the export destinations, Quick Export and Print) on the right.
- Latest-note dot: 5 pt `accent1Main`, 10 pt from the bottom-right corner, on the front note only
  (`showLatestNoteIndicator`).
- The editor comes from `Services.editorFactory.makeEditor()`; each pane owns one editor.
- Background = the theme's background; re-applied on appearance change, `Theme.didChange` and theme keys. The chrome
  follows the note in front: a slotted note uses the slotted theme pair when one is chosen
  (`slottedLightTheme` / `slottedDarkTheme`, `Theme.current(slotted:)`).
- Translucent (`translucent`, macOS 15+ only): a behind-window visual-effect view under the theme background at
  `translucencyOpacity` (0 = the bare material). The top and bottom bars then float on a `hudWindow` material blended
  within the window, or on the theme background with `solidBarsWhenTranslucent`.
- Pseudo-menu-bar mode drops the window down under the status item at `dropdownWidth × dropdownHeight`
  (`DropdownLayout`, kept on screen and above the window's minimum size).
- `present(inWindow:)` puts a view (Search) over the whole note area; navigating to a note removes it.
- Frame is autosaved (`setFrameAutosaveName`) in normal presence modes.
- Closing the window hides it (the app keeps running); ⌘Q quits.

## Deck navigation

Evidence: `SwipeGestureDetector.Coordinator` (local event monitor), `NotesManagement` (_currentIndex,
previouslyViewedIndex, deletedNotes), strings "Swipe between notes", "Swipe horizontally on the trackpad to
move to the previous or next note.", "Swipe sensitivity", "Higher values require more deliberate swipes.",
"Empty note deleted", "Jumped to latest", "Note is already first", "Create a new note after",
"Start with a new note", "Use latest empty note", tutorial "[←] Swipe or ⌘+[ to see the previous note."

- The deck is `Services.store.deck` minus slotted notes, front (newest) first. Index 0 = latest. With
  `showArchivedInStack`, archived notes follow at the back.
- Launch opens the last note shown; "Start with a new note" (`startWithNewNote`) opens a fresh one (an empty front
  note is reused); "Use slotted notes as your main notes" (`slottedAsMain`) opens the first slotted note.
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
  long, Super Notes shows the front note if it is empty, otherwise creates a new note.
- Jump to Front (⌘1) jumps to the front.
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
- The slot bar is a floating capsule (55% of the width, 24 pt, 16 pt up) of nine planets, Mercury → Pluto, in
  `typeLight` with the open slot in `accent1Main`; hovering names the planet and its note. It shows when
  `alwaysShowSlotsBar`, for 2 s after a slot is used, and with the bottom bar when slots are in use. Clicking a
  planet opens its slot (the open one goes back to the deck); an empty one takes the current note.
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

`MainMenu.build` is the single source for the menu bar and the Settings → Shortcuts list. Order, titles and
default keys follow the reference app's command table (see `ui-parity.md`). Every item built with a shortcut is
rebindable: Settings → Shortcuts shows a recorder per item, `Defaults[.menuShortcuts]` keeps the overrides by
`MenuLogic.bindingID` (nil = no shortcut) and `MenuState.applyBindings()` rewrites the items' key equivalents as soon as
they change, so menus, chrome tooltips and the Shortcuts list update together. A shortcut another item already uses
is refused with its name; "Restore Defaults" clears every override.
App: About, Settings… ⌘,, Services, Hide ⌘H, Hide Others ⌥⌘H, Show All, Quit ⌘Q.
File: Create New Note ⌘N, Move Note to Front ⇧⌘1, Search All Notes ⌘F, Command Palette… ⌘K, Find and Replace ⇧⌘F,
Toggle Split Screen ⇧⌘T, Swap Ephemeral vs. Slotted ⌘T, Make Read-Only/Allow Editing ⇧⌘R, Archive/Unarchive ⇧⌘A,
Lock/Unlock ⇧⌘L, Relock Notes, Delete Note ⌘D, Recover Notes from The Void..., Empty The Void, Print... ⇧⌘P,
Export Note ▸ (Quick Export ⌘S when a destination is chosen, then files, then "Send to …" apps), Close Window ⌘W.
Edit: Undo/Redo, Cut/Copy/Paste, Select All, Copy All ⌥⌘C, Select Line ⌘L, Find Next ⌘G, Find Previous ⇧⌘G,
Check Off Current Line ⇧⌘K, Cycle List Type ⇧⌘M, Indent ⌥⌘], Outdent ⌥⌘[, Move Line Up/Down ⌥↑/⌥↓, Duplicate
Line Up/Down ⌥⇧↑/⌥⇧↓, Markdown: Strikethrough ⇧⌘X, Expand All Links ⌥⌘L, Extension Autocomplete ⌃Space.
Appearance: Increase/Decrease/Reset Text Size ⌘= ⌘- ⌥⌘0, Always Show Slots Bar, Split Horizontally, Enter Full
Screen ⌃⌘F.
Navigate: Jump to Front ⌘1, Show Previous Note ⌘[, Show Next Note ⌘], Go to Slot 1…9 ⌘1…⌘9 and Ephemeral Notes
⌘0 (only while `shellKitSlotNumberShortcuts` is on; ⌘1 then leaves Jump to Front), Assign to Slot ▸ (⌃⌘1…9,
Remove from Slot).
Support / Help: Show Tutorial Notes, Keyboard Shortcuts. Window: Pin Super Notes to Top/Unpin from Top ⌘P, Hide/Show
Super Notes ⌘O, Minimize ⌘M, Zoom, Bring All to Front.
Toggle items change their titles with state instead of showing checkmarks.

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
  Settings → Notes has "Relock locked notes" (immediately).
- "Ask to unlock automatically" (`autoUnlockDelay`): a locked note that stays in front for that long asks for Touch ID
  by itself; navigating away cancels it, and a cancelled prompt waits for the next visit.

## Settings window

A toolbar-tab preferences window (`NSTabViewController`, ~780 pt wide; the title is the tab name) with the
11 tabs of ui-reference.md §5 — General, Appearance, Editor, Notes, Keywords, Shortcuts, Timer, Export,
Extensions, Privacy, Updates — each a grouped SwiftUI form using the reference labels ("Antinote" → "Super Notes").
`showSettings(tab:)` routes ids, titles and old aliases (`SettingsTab(routing:)`: "copyPaste"/"writing"/"lists" →
Editor, "storage"/"sync"/"backups"/"advanced" → Notes, "math" → Keywords, "timers" → Timer, "about" → Updates).
Appearance picks themes from one grid of preview tiles with a sun (light mode) and moon (dark mode) button each.
Super Notes has no updater, so Updates shows the version and the tutorial button.

## Onboarding & icons

Evidence: `TutorialPreferences` (_showOnboarding), tutorial notes (welcome, math, sum/avg, count, timer, `/`
palette, slotted "first of nine"), `AppIconManager` (_style, _customIcon, applyIcon), strings
"Choose an image to use as the Antinote app icon", "The current Antinote icon.", "An image of your own.",
"App icon updated".

- First launch with an empty deck: seed tutorial notes in the reference's teaching order (ui-reference.md §11),
  in Super Notes' own wording — welcome, math, conversions, variables, breathe, sum, avg, count, list, timer, commands,
  screenshots, shortcuts — each ending with a "[←]" hint and using its feature live, plus one slotted note; set
  `onboardingCompleted`.
- App icons are drawn in code (`AppIconArt`): default, midnight, mint, sunset; "custom" uses a chosen image
  copied to `support/AppIcon.png`. Applied with `NSApp.applicationIconImage` at launch and on change.

## Module-private defaults

`shellKitCurrentNote`, `shellKitLastHidden`, `shellKitSplit`, `shellKitSplitHorizontal`, `shellKitSwapPanes`,
`shellKitNewNotesInEphemeral`.
