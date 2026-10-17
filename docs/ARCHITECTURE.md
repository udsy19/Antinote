# Architecture

Super Notes is a native macOS scratchpad written in Swift (Swift 5 language mode), built with SwiftPM and Apple
frameworks only — no third-party dependencies, no Xcode project. Deployment target: macOS 14.

```
Sources/
  SuperNotesCore/ contracts & utilities: Note model + NoteStoring, NoteMode + keywords, NoteAnalysis,
                  Services registry, typed Defaults + settings keys, Theme, shortcuts & global hotkeys,
                  Keychain, alerts/HUD, paths
  StorageKit/     SQLite note store, The Void, backups, encrypted iCloud Drive sync
  NoteEngine/     first-line modes, math (units, currencies, crypto, variables), sum/avg/count,
                  list markers, link shrinking, paste cleaning
  ExtensionsKit/  JavaScript extensions on JavaScriptCore, `::` commands, API bridge, bundled extensions
  EditorKit/      the plain-text editor: checklists, inline results, short links, code highlighting,
                  OCR drop, AutoPaste, Vim mode, find & replace
  ShellKit/       main window & presence, swipe deck, slots, hotkey, menus, settings, themes, locking, onboarding
  ToolsKit/       timers & pomodoro, export, URL scheme, command palette, The Void, search
  SuperNotes/     app target: wires modules together
  SuperNotesSelfTest/ headless logic tests (`swift run SuperNotesSelfTest`)
```

Modules depend only on `SuperNotesCore` and talk through the `Services` registry
(`Services.store`, `Services.analyzer`, `Services.editorFactory`, …), so each can be built and tested on its own.

Conventions: notes are plain text (formatting lives in the text itself — list markers, keywords); everything is
local unless a privacy switch allows a network call; UI code is `@MainActor`; no dead code.
