# StorageKit

Local persistence for notes (SQLite), The Void, backups, JSON export/import, and optional end-to-end encrypted
sync through the user's iCloud Drive folder. Implements `NoteStoring` and `SyncServicing` from JotterCore.

## What Antinote does (evidence)

Sources: the class digest (ivars/selectors), UI strings and the bundled `DataModel.md`.

- **Storage engine.** Antinote started on raw SQLite (`SQLiteManager`: `notesTable`, `noteDbIndex`, `isSlotted`,
  `antilinksTable`, `checklistItemsTable`, `statsTable`, `attachmentsTable`) and later migrated to Core Data
  (`CoreDataStack`, `CoreDataNotesManager`, `_migratedToCoreData`, file `cd-v1-notes.sqlite`). The Core Data model
  has `Note {id, created, lastModified, content, dbIndex, isSlotted, slotIndex, skippedURLs}` plus to-many
  `ChecklistItem`, `Antilink {fullUrl, shortenedUrl, range}` and `Attachment`.
- **Migrations are backed up first.** "This version of Antinote upgrades your notes database to a new format. A backup
  of the current database is made first, and nothing is deleted." / "wrote pre-migration backup".
  `MigrationRecords` keeps one-shot flags (`_didMigrateToEncryptedCloudKit_v1`, `_didBackfillSyncState_v1`).
- **Deck ordering.** `dbIndex` orders notes; selectors `reloadNotesFromDatabase:`, "Restore Note Order".
  Slotted notes are separate (`_slottedNoteViewModels`, `_slotedNotesLimit`, "Slot not available").
- **The Void.** "Move to The Void", "Recover Notes from The Void...", "Delete from The Void?", "There is no recovery
  beyond The Void.", `_trashRetentionRawValue` / `TrashRetentionOption`, `cdTrigger - autoEmptyTrash`.
  "Empty note deleted" — empty notes are discarded instead of kept.
- **Backups.** "Backups are timestamped copies stored next to your notes database.", "Auto-backups to keep",
  "New backups overwrite the oldest one.", `_autoBackupIntervalRawValue`. Restoring: "Your current notes are saved as a
  new backup first", "iCloud Sync will be turned off, so you can try backups without pushing anything at your other
  devices … when you turn it back on, these notes win".
- **Sync.** CloudKit with an encrypted private database (`CloudKitSyncManager`, `CloudKitStateStore`,
  `_encryptCloudKitData`, `reencryptedThisSession`, `_lastSyncDate`, `_syncError`), a debounced remote-change handler
  (`remoteChangeDebouncer`), and the conflict rule "Sync conflict: both versions kept". Preferences sync
  (`PreferencesSyncManager.defaultsDidChange:`, "Keeps settings, keywords, themes, and keyboard shortcuts the same on
  your other Macs.") and extension sync (`ExtensionCloudSync`) are separate switches.

## How Jotter implements it

### Database (`SQLiteNoteStore`, `SQLiteDatabase`)
- System SQLite C API (`import SQLite3`) at `JotterPaths.database` (path injectable for tests), `journal_mode=WAL`,
  `synchronous=NORMAL`, `foreign_keys=ON`.
- Versioned migrations keyed on `PRAGMA user_version`, each run in a transaction:
  v1 `notes(id, content, created, modified, changed, position, slot, is_locked, is_read_only, is_archived,
  deleted_at, links JSON)` + indexes (partial unique index on `slot`, position, deleted_at);
  v2 `sync_state(id, synced_changed)` — the per-note sync base.
- One table instead of Antinote's child tables: links are stored as JSON (`[ShortLink]`), checklists live in the text.
- `changed` is an internal revision time bumped by any synced-field change (content, flags, archive, Void);
  `modified` only moves when content changes (contract).
- All notes are cached in memory and written through; `changes` publishes `NoteStoreChange`.

### Deck, slots, archive, The Void
- Deck = non-deleted, non-archived notes by `position` (0 = front, contiguous). Archived notes are kept after the
  deck so positions stay unique among non-deleted notes. Void notes have position -1.
- `create` inserts at 0 and shifts the rest; `promoteToFront`, `move(_:toPosition:)` renumber the deck.
- `setSlot`: a slot belongs to at most one note (partial unique index); taking a used slot clears it on the other note.
- Archiving, voiding clear the slot. `moveToVoid` sets `deletedAt` and removes the note from the deck;
  `restoreFromVoid` and unarchiving put it at the front. `purgeExpiredVoid` uses `Defaults[.voidRetentionDays]`
  (0 = never) with an injectable clock. `deleteIfEmpty(_:)` drops a whitespace-only note permanently.
- `search`: case- and diacritic-insensitive substring over content, deck order, archived notes appended on request.

### Backups and portability
- `backup()` runs `VACUUM INTO` (consistent while open) into `JotterPaths.backups/notes-<timestamp>.sqlite` and keeps
  the newest `Defaults[.backupCount]`. `StorageKitModule`'s hourly maintenance makes one automatically once
  `Defaults[.backupIntervalHours]` (default 24) have passed, and moves ephemeral, unarchived notes not changed for
  `Defaults[.autoDeleteUnmodifiedDays]` days to The Void (0 = never; `Note.isUnmodified(since:)`).
- `restore(from:)` validates the file, saves the current notes as a new backup, closes the database, swaps the file
  (removing `-wal`/`-shm`), reopens, migrates, turns sync off and marks "local wins" for the next sync, then posts
  `.reloaded`. On failure the old database is reopened untouched.
- `exportJSON()` / `importJSON(_:)` — versioned JSON of all notes; import merges by id (newer `modified` wins,
  new notes appended to the end of the deck, taken slots dropped).

### Encrypted iCloud Drive sync (`ICloudDriveSync`, `SyncFolder`, `SyncMerge`, `SyncCrypto`, `KeychainSyncKey`)
CloudKit needs a paid developer account, so sync uses the iCloud Drive folder
`~/Library/Mobile Documents/com~apple~CloudDocs/Jotter/`:
- `notes/<id>.jnote` — AES-GCM (CryptoKit) sealed JSON `{note, changed}` or a tombstone `{id, deletedAt}`.
- `key.check` — a sealed marker proving which key encrypts the folder; `preferences.jprefs` — sealed plist of the
  synced Settings keys (only with `Defaults[.syncPreferences]`).
- Key: 256-bit, generated once, stored in the Keychain as a synchronizable item (iCloud Keychain carries it to other
  Macs). If the data-protection keychain is unavailable (unsigned builds) it falls back to a local item and the key can
  be moved by hand (`exportKey()`/`importKey(_:)`). A Mac that sees `key.check` but has no key waits:
  "Waiting for the encryption key from your other Mac".
- Merge (`SyncMerge.plan`, pure): per id, compare local `changed`, remote `changed` and the last synced base.
  Only one side changed → it wins; both changed with different content → newest wins and the other version is kept as
  a new note starting with a "Sync conflict" line; tombstones delete unless the other side edited after the base.
- Triggers: local store changes (debounced 2 s), a directory watcher (DispatchSource), 30 s polling, `syncNow()`.
  iCloud placeholders (`.name.icloud`) are asked to download and picked up on a later pass.
- `statusText`: "Sync is off", "iCloud Drive is off", "Waiting for the encryption key from your other Mac",
  "Syncing…", "Synced just now / 2 min ago", or the last error.

## Gaps
- Sync runs on the main actor with plain file I/O (no `NSFileCoordinator`); fine for a few thousand small notes.
- Deck order and slots are per-Mac (not synced). Extension sync is not implemented here.
