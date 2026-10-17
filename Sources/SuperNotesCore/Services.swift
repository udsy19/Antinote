import AppKit

// MARK: - Extensions

public struct ExtensionCommandInfo: Identifiable, Hashable, Sendable {
    public var id: String { "\(extensionName).\(name)" }
    public var name: String
    public var aliases: [String]
    public var extensionName: String
    public var helpText: String
    /// e.g. "::today(days)" — shown in autocomplete.
    public var signature: String
    /// What the command does with its result: "insert", "replaceLine", "replaceAll" or "openURL".
    public var action: String
    public init(name: String, aliases: [String], extensionName: String, helpText: String, signature: String, action: String) {
        self.name = name; self.aliases = aliases; self.extensionName = extensionName
        self.helpText = helpText; self.signature = signature; self.action = action
    }
}

public enum ExtensionEdit: Sendable, Equatable {
    /// Insert text at the command's position (the `::command(...)` text is removed).
    case insert(String)
    /// Replace the command's whole line.
    case replaceLine(String)
    /// Replace the entire note.
    case replaceAll(String)
    case openURL(URL)
    /// Show a message without changing the note.
    case message(String)
    case failure(String)
}

@MainActor
public protocol ExtensionsServicing: AnyObject {
    var commands: [ExtensionCommandInfo] { get }
    /// Commands whose name or alias starts with `prefix` (for `::` autocomplete).
    func complete(_ prefix: String) -> [ExtensionCommandInfo]
    /// Runs a `::name(args)` invocation found on `line` of `note`.
    func run(invocation: String, line: String, note: String, completion: @escaping (ExtensionEdit) -> Void)
    func reload()
    /// The extension manager (installed extensions, preferences, API keys, community extensions) for Settings.
    func makeSettingsView() -> NSView
}

// MARK: - Other services

@MainActor
public protocol TimerServicing: AnyObject {
    /// Starts (or resumes) the timer described by a `timer…` note's arguments.
    func start(noteID: UUID, arguments: String)
    func stop(noteID: UUID)
    func isRunning(noteID: UUID) -> Bool
    /// Text shown in the note while running, e.g. "12:04 · work".
    func status(noteID: UUID) -> String?
    /// Plays the alert sound at the volume set in Settings → Timer (its Test button).
    func playAlertSound()
    /// Whether any timer is counting right now (paused and finished ones don't count).
    var hasRunningTimer: Bool { get }
}

@MainActor
public protocol SyncServicing: AnyObject {
    var isEnabled: Bool { get }
    var statusText: String { get }
    func syncNow()
    /// The encryption key as text, for moving it to another Mac by hand when Keychain sync isn't available.
    func exportKey() -> String?
    func importKey(_ text: String) throws
}

@MainActor
public protocol WindowServicing: AnyObject {
    func showMain()
    func toggleMain()
    func show(noteID: UUID)
    func showSettings(tab: String?)
    /// The note currently shown in the main window.
    var currentNoteID: UUID? { get }
    /// Shows `view` over the whole note area of the main window (Search replaces the note in place);
    /// nil removes it and refocuses the note.
    func present(inWindow view: NSView?)
    /// Whether the main window is on screen, and whether it has keyboard focus (UpdateKit waits for an idle moment).
    var isMainWindowVisible: Bool { get }
    var isMainWindowKey: Bool { get }
    /// Whether an editor holds typing that hasn't been written to the store yet.
    var hasUnsavedEdits: Bool { get }
}

/// One command of the ⌘K palette. The editor's inline "/" list offers the same commands.
public struct PaletteCommand {
    public var title: String
    public var detail: String?
    public var symbol: String
    /// Right-aligned hint, e.g. a shortcut or "Slot 2".
    public var trailing: String?
    /// Extra searchable words (they rank below title matches).
    public var keywords: String
    /// Set for "go to note" commands, so full-text hits don't repeat them.
    public var noteID: UUID?
    /// Set for "Insert Keyword" commands: the keyword that becomes the note's first line. The editor makes that
    /// change itself, as one undoable edit; everywhere else `action` writes the note.
    public var keyword: String?
    public var action: () -> Void

    public init(title: String, detail: String? = nil, symbol: String, trailing: String? = nil, keywords: String = "",
                noteID: UUID? = nil, keyword: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.detail = detail; self.symbol = symbol; self.trailing = trailing
        self.keywords = keywords; self.noteID = noteID; self.keyword = keyword; self.action = action
    }
}

/// Floating panels owned by ToolsKit.
@MainActor
public protocol PanelServicing: AnyObject {
    func showCommandPalette()
    func showVoid()
    /// Asks, then permanently deletes every note in The Void.
    func emptyVoid()
    func showSearch()
    /// The palette's commands matching `query` (fuzzy, best first; every command for an empty query), without its
    /// note matches.
    func commands(matching query: String) -> [PaletteCommand]
}

@MainActor
public protocol ExportServicing: AnyObject {
    func export(_ note: Note, to destination: ExportDestination)
    /// Shows the print panel for a note (keyword line omitted per Settings).
    func print(_ note: Note)
    func exportAll(to folder: URL) throws
}

/// Late-bound registry; the app target assigns implementations at launch.
@MainActor
public enum Services {
    public static var store: NoteStoring!
    public static var analyzer: NoteAnalyzing!
    public static var extensions: ExtensionsServicing!
    public static var timers: TimerServicing!
    public static var sync: SyncServicing!
    public static var windows: WindowServicing!
    public static var export: ExportServicing!
    public static var editorFactory: EditorFactory!
    public static var panels: PanelServicing!
}

public enum SuperNotesPaths {
    public static let bundleID = Bundle.main.bundleIdentifier ?? "com.udsy.supernotes"
    /// The folder `support` lives in: Application Support. The self-test and render tools point it at a temporary
    /// folder so they never create or touch the real one.
    nonisolated(unsafe) public static var base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    public static let supportFolderName = "Super Notes"
    public static var support: URL { ensure(base.appendingPathComponent(supportFolderName, isDirectory: true)) }
    public static var database: URL { support.appendingPathComponent("notes.sqlite") }
    public static var backups: URL { ensure(support.appendingPathComponent("Backups", isDirectory: true)) }
    public static var extensions: URL { ensure(support.appendingPathComponent("Extensions", isDirectory: true)) }
    public static var themes: URL { ensure(support.appendingPathComponent("Themes", isDirectory: true)) }
    @discardableResult public static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

// MARK: - Editor (EditorKit implements, ShellKit hosts)

/// Commands the window/menus send to the editor.
public enum EditorCommand: String, CaseIterable, Sendable {
    case toggleCheckbox, cycleListStyle, indent, outdent, moveLineUp, moveLineDown, duplicateLineUp, duplicateLineDown
    case strikethrough, find, findAndReplace, findNext, findPrevious, increaseTextSize, decreaseTextSize, resetTextSize
    case copyAll, selectLine, expandAllLinks, showExtensionAutocomplete
}

@MainActor
public protocol NoteEditing: AnyObject {
    /// The editor's root view, ready to embed.
    var view: NSView { get }
    var note: Note? { get }
    /// Shows a note (saving is the editor's job: it writes changes back through `Services.store`).
    func load(_ note: Note)
    func focus()
    func perform(_ command: EditorCommand)
    /// Inserts text at the cursor (AutoPaste, OCR results, URL scheme appends).
    func insert(_ text: String)
    /// Writes pending edits to the store now (saving is otherwise debounced); called before hiding or quitting.
    func flush()
    /// Whether there are edits `flush()` would write.
    var hasUnsavedChanges: Bool { get }
    /// Called after every content change with the latest analysis (window chrome shows mode/summary/timer).
    var onAnalysis: ((NoteAnalysis) -> Void)? { get set }
}

@MainActor
public protocol EditorFactory: AnyObject {
    func makeEditor() -> NoteEditing
}
