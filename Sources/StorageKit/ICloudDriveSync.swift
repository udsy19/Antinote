import Foundation
import Combine
import CryptoKit
import SuperNotesCore

extension Defaults.Keys {
    /// Last local change to a synced preference (drives preferences last-writer-wins).
    static let storagePrefsChangedAt = Key<Date>("storageKit.prefsChangedAt", default: .distantPast)
}

/// End-to-end encrypted sync through the user's iCloud Drive folder (`…/CloudDocs/Super Notes`). Active only while
/// `Defaults[.syncNotes]` is on; preferences ride along with `Defaults[.syncPreferences]`.
@MainActor
public final class ICloudDriveSync: SyncServicing {
    private enum State: Equatable {
        case off, driveOff, waitingForKey, keyMismatch, downloading, syncing, synced(Date), failed(String)
    }

    nonisolated public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Super Notes", isDirectory: true)
    }

    private let store: SQLiteNoteStore
    private let root: URL
    private let keyStore: SyncKeyStoring
    private var folder: SyncFolder?
    private var state: State = .off
    private var lastConflicts = 0
    private var bag: Set<AnyCancellable> = []
    private var pollTimer: Timer?
    private var watcher: DispatchSourceFileSystemObject?
    private var watcherDebounce: AnyCancellable?
    private var applying = false

    init(store: SQLiteNoteStore, root: URL = ICloudDriveSync.defaultRoot, keyStore: SyncKeyStoring) {
        self.store = store
        self.root = root
        self.keyStore = keyStore
    }

    public convenience init(store: SQLiteNoteStore) {
        self.init(store: store, keyStore: KeychainSyncKey())
    }

    public var isEnabled: Bool { Defaults[.syncNotes] }

    public var statusText: String {
        switch state {
        case .off: return "Sync is off"
        case .driveOff: return "iCloud Drive is off"
        case .waitingForKey: return "Waiting for the encryption key from your other Mac"
        case .keyMismatch: return "This Mac's encryption key doesn't match the one your other Macs use"
        case .downloading: return "Waiting for iCloud Drive to download…"
        case .syncing: return "Syncing…"
        case .failed(let message): return "Sync failed: \(message)"
        case .synced(let date):
            let seconds = Date().timeIntervalSince(date)
            let when = seconds < 60 ? "just now" : seconds < 3600 ? "\(Int(seconds / 60)) min ago" : "\(Int(seconds / 3600)) h ago"
            var text = "Synced \(when)"
            if lastConflicts > 0 { text += " · \(lastConflicts) conflict\(lastConflicts == 1 ? "" : "s") kept as new notes" }
            if !keyStore.isShared { text += " · key stored on this Mac only" }
            return text
        }
    }

    /// Starts observing settings, local edits, the folder, and a 30-second poll.
    public func start() {
        Defaults.changes
            .filter { [Defaults.Keys.syncNotes.name, Defaults.Keys.syncPreferences.name].contains($0) }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.configure() } }
            .store(in: &bag)
        store.changes
            .filter { [weak self] _ in MainActor.assumeIsolated { self?.applying == false } }
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.syncIfEnabled() } }
            .store(in: &bag)
        Defaults.changes
            .filter { name in PreferencesSync.keyNames.contains(name) }
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.applying else { return }
                    Defaults[.storagePrefsChangedAt] = Date()
                }
            }
            .store(in: &bag)
        Defaults.changes
            .filter { $0 == Defaults.Keys.storagePrefsChangedAt.name }
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.syncIfEnabled() } }
            .store(in: &bag)
        configure()
    }

    private func configure() {
        pollTimer?.invalidate(); pollTimer = nil
        watcher?.cancel(); watcher = nil
        guard isEnabled else { state = .off; folder = nil; return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncIfEnabled() }
        }
        syncNow()
        watchFolder()
    }

    private func watchFolder() {
        let dir = root.appendingPathComponent("notes", isDirectory: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                               queue: .main)
        let debounce = PassthroughSubject<Void, Never>()
        watcherDebounce = debounce.debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] in MainActor.assumeIsolated { self?.syncIfEnabled() } }
        source.setEventHandler { debounce.send() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func syncIfEnabled() {
        if isEnabled { syncNow() }
    }

    public func syncNow() {
        guard isEnabled else { state = .off; return }
        guard FileManager.default.fileExists(atPath: root.deletingLastPathComponent().path) else { state = .driveOff; return }
        guard let folder = resolveFolder() else { return }
        state = .syncing
        applying = true
        defer { applying = false }
        do {
            let localWins = Defaults[.storageSyncLocalWins]
            let plan = try folder.sync(store, localWins: localWins)
            if localWins { Defaults[.storageSyncLocalWins] = false }
            if Defaults[.syncPreferences] { try PreferencesSync.sync(folder: folder) }
            lastConflicts = plan.conflicts
            state = .synced(Date())
            if watcher == nil { watchFolder() }
        } catch {
            Log.sync.error("sync failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// Finds or creates the key and checks it against the folder's `key.check`.
    private func resolveFolder() -> SyncFolder? {
        if let folder { return folder }
        let key = keyStore.load()
        switch SyncFolder.keyCheckState(root: root, key: key) {
        case .downloading:
            state = .downloading; return nil
        case .mismatch:
            state = key == nil ? .waitingForKey : .keyMismatch; return nil
        case .matches:
            folder = SyncFolder(root: root, key: key!)
        case .missing:
            let key = key ?? SymmetricKey(size: .bits256)
            do {
                try keyStore.save(key)
                let f = SyncFolder(root: root, key: key)
                try f.writeKeyCheck()
                folder = f
            } catch {
                state = .failed(error.localizedDescription); return nil
            }
        }
        return folder
    }

    // MARK: Manual key transfer (when iCloud Keychain can't carry the key)

    /// The sync key as text, for moving it to another Mac by hand.
    public func exportKey() -> String? {
        keyStore.load().map { $0.withUnsafeBytes { Data($0) }.base64EncodedString() }
    }

    public func importKey(_ text: String) throws {
        guard let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)), data.count == 32 else {
            throw StorageError(message: "That isn't a Super Notes sync key.")
        }
        try keyStore.save(SymmetricKey(data: data))
        folder = nil
        syncNow()
    }
}

/// Last-writer-wins sync of the shared Settings keys as one encrypted property list.
@MainActor
enum PreferencesSync {
    /// Settings that make sense on every Mac (not per-machine paths, login items or privacy/sync switches).
    static let keyNames: Set<String> = Set(([
        .appPresence, .globalHotkey, .menuShortcuts, .pinOnTop, .restorePinState, .hideOnFocusLoss, .newNoteAfterMinutes,
        .swipeNavigation, .swipeSensitivity, .showLatestNoteIndicator, .showNoteDates, .alwaysShowSlotsBar, .forceRTL,
        .startWithNewNote, .dropdownWidth, .dropdownHeight,
        .lightTheme, .darkTheme, .paperType, .paperOpacity, .fontName, .textSize, .doubleFontSize, .lineSpacing, .translucent, .appIcon,
        .solidBarsWhenTranslucent, .translucencyOpacity, .showBottomBar, .showNoteCount, .showCreationDate,
        .slottedLightTheme, .slottedDarkTheme,
        .vimMode, .keepIndentOnReturn, .allowTextReplacements, .shortenLinks, .detectLinks,
        .checkSpelling, .autocorrectSpelling, .autoCapitalize, .smartQuotes, .smartDashes, .checkGrammar,
        .vimMotionTimeout, .autoCopySelection, .caretOffset, .caretOffsetInLists,
        .defaultListStyle, .checkedItemBehavior, .listContinuity, .inlineCheckboxes, .inlineBullets, .inlineNumbered,
        .checkTriggers,
        .primaryCurrency, .secondaryCurrency, .decimalPlaces, .showCurrencySymbol, .autoUpdateRates, .preventEditingAnswers, .customRates,
        .cleanPaste, .pasteRemoveMarkdown, .pasteRemoveBullets, .pasteRemoveNumbering, .pasteRemoveLeadingWhitespace,
        .pasteRemoveEmptyLines, .copyWholeNoteWhenNoSelection, .cutLineWhenNoSelection, .skipKeywordWhenCopying,
        .copyListItemsUnchecked, .skipListMarkersWhenCopying, .extraKeywords, .mainKeywords, .keywordsEnabled,
        .countdownNotification, .countdownFullScreen, .countdownSound, .pomodoroNotification, .pomodoroFullScreen,
        .pomodoroSound, .timerVolume,
        .timerInMenuBar, .pauseTimersOnQuit, .pomodoroWorkMinutes, .pomodoroBreakMinutes,
        .voidRetentionDays, .backupCount, .backupIntervalHours, .autoDeleteUnmodifiedDays, .showArchivedInStack,
        .autoUnlockDelay, .slottedAsMain, .relockAfterMinutes, .exportDestinations, .quickExportDestination,
        .omitKeywordInExport, .exportFirstLineAsTitle, .customURLTemplate, .extensionsEnabled,
    ] as [Defaults.Keys]).map(\.name))

    static func sync(folder: SyncFolder) throws {
        let localChanged = Defaults[.storagePrefsChangedAt]
        if let remote = folder.readPreferences() {
            if remote.changed > localChanged {
                apply(remote.values, changed: remote.changed)
            } else if localChanged > remote.changed {
                try folder.writePreferences(changed: localChanged, values: snapshot())
            }
        } else {
            let changed = localChanged == .distantPast ? Date() : localChanged
            try folder.writePreferences(changed: changed, values: snapshot())
            Defaults[.storagePrefsChangedAt] = changed
        }
    }

    static func snapshot() -> [String: Any] {
        var values: [String: Any] = [:]
        for name in keyNames { if let v = Defaults.store.object(forKey: name) { values[name] = v } }
        return values
    }

    /// Writes remote values (absent keys revert to defaults) and announces each change.
    static func apply(_ values: [String: Any], changed: Date) {
        for name in keyNames.sorted() {
            if let v = values[name] { Defaults.store.set(v, forKey: name) } else { Defaults.store.removeObject(forKey: name) }
        }
        Defaults[.storagePrefsChangedAt] = changed
        for name in keyNames.sorted() { Defaults.changes.send(name) }
    }
}
