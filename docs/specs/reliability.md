# Reliability and data loss (FMEA)

Every way text typed into Super Notes could go missing, what should happen instead, what the code did before this
audit, what changed, and which self-test drills it. Tests live in `Sources/SuperNotesSelfTest/ReliabilityTests.swift`
(`Reliability.*`) unless noted; all of them work in throwaway folders and never touch the real Application Support.

## How saving works now

1. **Keystroke** → the editor writes `Drafts/<note id>.json` (atomic, coalesced on a background queue:
   `NoteDrafts`). This is the write-ahead copy.
2. **0.3 s later** (or at once on switching notes, hiding the window, quitting, a URL/palette command, restore) the
   editor calls `store.update`.
3. **`SQLiteNoteStore.persist`** writes one transaction in WAL mode with `synchronous = FULL`: the commit is on disk
   before the call returns. A failure (full disk, read-only file) keeps the previous version on disk and the new text
   in memory, marks the note in `unsavedNoteIDs`, reports it once through `saveFailures` (a pill in plain words) and
   retries every later write and every 15 s. The draft file stays until the write lands.
4. **Quit** (`willTerminate`): editors flush, failed writes are retried, what still won't go in is written to
   `unsaved-notes-<time>.json` next to the database (importable from Settings), the WAL is checkpointed.
5. **Launch**: `quick_check` on the database; a damaged file is moved into `Backups/` as `notes-<time>-damaged.sqlite`
   (with its `-wal`/`-shm`) and the newest readable backup is restored, else a fresh database starts — always with
   an alert. Draft files are put back ("Recovered unsaved text"). Notes written into a fallback database while the
   real one couldn't open are merged back.

## Failure modes

| Area | Scenario | Expected | Before | Fix | Test |
|---|---|---|---|---|---|
| Typing | App crash / kill -9 / force quit between a keystroke and the 0.3 s save | Text comes back at next launch | Up to 0.3 s of typing lost (silently) | Draft file per keystroke; `StorageKitModule.recoverDrafts` at launch, "Recovered unsaved text" | `draftRecovery`, `editorDraftFile` |
| Typing | Power loss right after a save | Saved text is on disk | `synchronous = NORMAL`: a power cut could roll back the last commits | `synchronous = FULL` (fsync per commit) + draft file | `diskFull` (durability path), structural |
| Typing | Logout / restart / Quit | Every editor flushes before exit | Flush on `willTerminate` | Unchanged; storage's own `willTerminate` handler calls `flushEdits()` itself so observer order can't matter, then retries unsaved writes and checkpoints | structural |
| Typing | Window hidden with ⌥A | Flushed | `hideMain` flushes | Unchanged | structural |
| Typing | Switching notes within the 0.3 s debounce | The note keeps the typing | **Data loss.** `freshNote` merged the editor's *last saved* copy; a note typed into for < 0.3 s read as blank, `leaveIfBlank` deleted it permanently, then the pending save hit a missing row | `freshNote` flushes the editor first; `navigate`/`newNote`/`leaveIfBlank` all read the real text | `switchNoteMidDebounce` (fails on the old code: content `nil`) |
| Typing | Sleep / wake | Nothing to do: saves are synchronous and debounced in wall-clock time | ok | — | — |
| Typing | Update installs (UpdateKit swap) | Flush before the old bundle moves | Idle install requires `!hasUnsavedEdits`; the swap helper only acts after the process has exited, and exit runs the flush | Unchanged (verified) | `UpdateKit.*` |
| Typing | Undo history vs save | Undo never resurrects unsaved state | Per-note histories; saves are content snapshots | Unchanged | `UndoTests` |
| Typing | IME composition when a save or sync reload lands | Composition text is in `textView.string` and saved as is; a reload is skipped while a save is pending | ok | — | accepted |
| Typing | 10 MB paste | Stored and exported intact | ok | Draft writes are coalesced (latest wins) so a burst never queues 10 MB per key | `oddTextRoundTrips` |
| Typing | Binary / garbage paste containing NUL | Stored intact | **Silent truncation** at the first NUL: `sqlite3_bind_text(…, -1)` and `String(cString:)` | Bind by byte count, read by `sqlite3_column_bytes` | `oddTextRoundTrips` |
| Typing | Emoji, ZWJ sequences, flags, combining marks, RTL marks, BOM | Round-trip through SQLite and JSON | ok | — | `oddTextRoundTrips` |
| Storage | Disk full during save | Previous version intact, new text kept in memory, clear message, retried | Error only logged; nothing retried; the note looked saved; on quit the text was gone | `unsavedNoteIDs` + `saveFailures` pill + retry timer + emergency JSON on quit; draft file stays | `diskFull`, `emergencyExport`, `editorDraftFile` |
| Storage | Database file damaged at launch | Recover from the newest good backup, keep the damaged file, tell the user | Alert, then a **temporary** database that vanished on quit | `StorageError.kind == .damaged` → `SQLiteNoteStore.recover` | `damagedDatabaseRestoresBackup` (header garbage and torn body) |
| Storage | Downgrade after an update (schema newer than this build) | File untouched, user told to update, new notes kept and merged later | Alert + temporary database (lost on quit) | `.newerVersion` → fallback `notes-fallback.sqlite` next to the database; `absorb(fallback:)` merges it back on the next healthy launch | `newerSchemaLeavesFileAlone` |
| Storage | Application Support missing / read-only / permissions changed | Never treated as "damaged"; file never moved | Alert + temporary database | Non-damage errors open the fallback file (support folder, else temp) and merge back later; a read-only file keeps notes in memory and reports | `readOnlyFile` |
| Storage | Database locked by another process | Wait up to 3 s (`busy_timeout`), then the write fails into the retry path | Error only logged | Covered by the unsaved/retry path | `diskFull` (same path) |
| Storage | Two instances of the app | Only one runs | Possible (two in-memory caches overwrite each other) | `LSMultipleInstancesProhibited` in Info.plist | structural |
| Storage | WAL checkpointing | WAL never grows without bound; folded at quit | Automatic checkpoints only | `checkpoint()` hourly and at quit | structural |
| Storage | Migration from Jotter | Nothing deleted; folders move only into an empty spot | ok | — | `StorageKit.legacyMigration` |
| Storage | Schema upgrade | Pre-migration copy made first; migration transactional | ok | Pre-migration copies are now outside the backup rotation | `StorageKit.migrations`, `backupRotationSparesSafetyCopies` |
| Storage | Backup rotation deletes the last good copy | Rotation only touches routine backups; the newest always stays | A backup that failed half-way (full disk) could count as the newest and push a good one out; `pre-migration` copies were rotated away | Partial copy removed on failure; `isRotated` excludes tagged copies; `max(count, 1)` | `backupRotationSparesSafetyCopies` |
| Storage | Restore from backup | Validated first; current notes backed up; sync off; typing not written over the restored note at quit | `Maintenance.restore` didn't flush, so the quit flush could write the editor's text over the restored note | `flushEdits()` before `restore` | `StorageKit.backupRestore` |
| Storage | Export / import round trip | Every field survives | ok (dates to the second: ISO 8601) | — | `exportImportAllFields` |
| Storage | Truncated / foreign import file | Refused whole, nothing half-applied | ok | — | `exportImportAllFields` |
| Storage | iCloud Drive folder offline or conflicted | Sync pauses; the merge is per-note with conflict copies, never a silent overwrite | ok (see storagekit.md) | — | `StorageKit.folderSync`, `mergeRules` |
| The Void | Retention purge | Only Void notes older than the retention; slotted, archived and live notes never | ok | — | `retentionSparesLiveNotes` |
| The Void | "Auto-delete unmodified notes" | Only ephemeral deck notes | ok | — | `retentionSparesLiveNotes` |
| The Void | `deleteIfEmpty` on a note with content | Never deletes text; `[ ]` counts as content | ok at the store; the shell's stale read was the bug above | `freshNote` flush | `retentionSparesLiveNotes`, `switchNoteMidDebounce` |
| The Void | URL `supernotes://overwrite` from another app | Old text kept | **Silent overwrite** of the current note; `append`/`overwrite` also worked from stale text while typing | Old text copied into The Void ("Previous text moved to The Void"); editors flushed first; locked and read-only notes refuse | `urlOverwriteKeepsOldText` |
| Palette | "Insert Keyword" / append a `::command` while typing | Applied to the live text | Worked from stale text; the pending save then overwrote the change | `flushEdits()` first | structural |
| Locking | Touch ID unavailable or fails | Password fallback (`deviceOwnerAuthentication`); without any, an alert; the text is still in the database and exports | ok | — | accepted |
| Extensions | `::ask` etc. throws, hangs or returns huge output | Runs on the extension's own queue; HTTP 60 s and AI 10 min timeouts; cancel; result inserted as one undoable edit | ok | — | `ExtensionsKit.*` |
| AI | Model download interrupted / corrupt / disk short | Resumed by range, SHA-256 verified before use, 10 GB free required | ok | — | `AIKit.downloadManager` |
| AI | CLI engine missing or hangs | Timeout then SIGKILL | ok | — | `AIKit.commandLineEngine` |
| Timers | Sleep / restart | Persisted in Defaults on every change and at quit; resumed | ok | — | `ToolsKit.*` |
| Settings | Corrupt preference values | Defaults never crash: wrong types read as the default; counts clamped | ok | — | `settingsGarbage` |
| Lifecycle | Launch while the previous instance is quitting | `busy_timeout` 3 s covers the checkpoint; the second instance is refused anyway | ok | `LSMultipleInstancesProhibited` | structural |
| Lifecycle | Update fails mid-swap | Helper puts the old bundle back; data folder untouched (it's in Application Support) | ok | — | `UpdateKit.swapScript` |
| Lifecycle | First launch with existing data | Opens, migrates with a backup first | ok | — | `StorageKit.migrations` |

## Accepted risks

- `synchronous = FULL` costs one fsync per save (every 0.3 s of continuous typing at most); fine on an SSD.
- A second *copy* of the app at another path can still run alongside (LaunchServices only blocks the same bundle);
  SQLite keeps the file consistent but each instance's in-memory cache is its own, so the last writer wins per note.
- Drafts hold the current note's text in plain form under Application Support (as the database itself does);
  locked notes are not encrypted at rest either.
- The export's ISO 8601 dates lose sub-second precision; "newer wins" on import compares whole seconds.
- A sync conflict that lands while the local note is mid-composition reloads after the pending save, not during it.
- Damage inside a page that `quick_check` passes is handled by SQLite as `SQLITE_CORRUPT` at first touch, which
  goes through the same recovery on the next launch, not immediately.
