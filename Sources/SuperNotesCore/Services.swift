import AppKit
import Combine

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
    /// What goes between the parentheses, in order (the editor's parameter hint).
    public var parameters: [ExtensionParameter]
    /// Without `parameters`, the names come from `signature` (see `ExtensionParameter.parse(signature:)`).
    public init(name: String, aliases: [String], extensionName: String, helpText: String, signature: String, action: String,
                parameters: [ExtensionParameter]? = nil) {
        self.name = name; self.aliases = aliases; self.extensionName = extensionName
        self.helpText = helpText; self.signature = signature; self.action = action
        self.parameters = parameters ?? ExtensionParameter.parse(signature: signature)
    }
}

/// One argument of a `::command(…)`, as the parameter hint describes it.
public struct ExtensionParameter: Hashable, Sendable {
    public var name: String
    /// What to write, short and plain ("how many days from today"); empty when the extension says nothing.
    public var summary: String
    public var isOptional: Bool
    /// What an optional parameter is when left out, as written in a note ("0", "iso"); nil when there is nothing
    /// worth showing.
    public var defaultValue: String?
    /// A value or two to copy ("3 or -1").
    public var example: String?
    /// Plain text: as the last parameter it keeps any further commas ("::pick(pizza, sushi, tacos)").
    public var isText: Bool

    public init(name: String, summary: String = "", isOptional: Bool = false, defaultValue: String? = nil, example: String? = nil,
                isText: Bool = false) {
        self.name = name; self.summary = summary; self.isOptional = isOptional
        self.defaultValue = defaultValue; self.example = example; self.isText = isText
    }

    /// The parameters named in a signature, for extensions (and callers) that only give one: "::today(days?, format)"
    /// → days (optional), format. "name?", "[name]" and "name = value" mark optional parameters; no parentheses, or
    /// empty ones, mean none.
    public static func parse(signature: String) -> [ExtensionParameter] {
        guard let open = signature.firstIndex(of: "(") else { return [] }
        return InvocationArguments.scan(signature[signature.index(after: open)...]).raw.compactMap { raw in
            var text = raw.trimmingCharacters(in: .whitespaces)
            var optional = false, defaultValue: String?
            if text.hasPrefix("["), text.hasSuffix("]") { text = String(text.dropFirst().dropLast()); optional = true }
            if let eq = text.firstIndex(of: "=") {
                let value = text[text.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                defaultValue = value.isEmpty ? nil : value
                text = String(text[..<eq]); optional = true
            }
            text = text.trimmingCharacters(in: .whitespaces)
            if text.hasSuffix("?") { text.removeLast(); optional = true }
            text = text.trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : ExtensionParameter(name: text, isOptional: optional, defaultValue: defaultValue)
        }
    }
}

/// The text after a `::name(`, split into arguments the one way both the extension runner and the editor's parameter
/// hint read it: top-level commas separate arguments; quotes ("…", '…' or “…”, opened only at the start of an
/// argument, with `\` escapes inside) and nested parentheses keep their commas; the first top-level ")" ends the list.
public struct InvocationArguments: Equatable, Sendable {
    /// Each argument's text as written: quotes kept, untrimmed. Always at least one (possibly empty).
    public var raw: [String]
    /// Where the closing ")" is in the scanned text; nil when the text ran out first.
    public var close: String.Index?
    /// The text ran out inside a quote.
    public var inQuote: Bool
    /// Open parentheses inside the current argument when the text ran out.
    public var depth: Int

    public static func scan(_ body: Substring) -> InvocationArguments {
        var parts: [String] = [], current = ""
        var quote: Character?, escaped = false, depth = 0
        var index = body.startIndex
        while index < body.endIndex {
            let c = body[index]
            if let q = quote {
                current.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == q { quote = nil }
            } else {
                switch c {
                case "\"", "'", "“":
                    // Quotes only open an argument; an apostrophe inside a word ("don't") is plain text.
                    if current.trimmingCharacters(in: .whitespaces).isEmpty { quote = c == "“" ? "”" : c }
                    current.append(c)
                case "(": depth += 1; current.append(c)
                case ")" where depth > 0: depth -= 1; current.append(c)
                case ")":
                    parts.append(current)
                    return InvocationArguments(raw: parts, close: index, inQuote: false, depth: 0)
                case "," where depth == 0: parts.append(current); current = ""
                default: current.append(c)
                }
            }
            index = body.index(after: index)
        }
        parts.append(current)
        return InvocationArguments(raw: parts, close: nil, inQuote: quote != nil, depth: depth)
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

// MARK: - AI

/// Which engine answers `::ask` and the other AI commands (Settings → AI).
public enum AIEngineKind: String, Codable, CaseIterable, Sendable {
    /// The downloaded llama.cpp model, run on this Mac.
    case onDevice
    /// Apple's on-device model (macOS 26 and later, where the Mac has it).
    case apple
    /// A command-line tool the user installed and signed in to, run as a subprocess.
    case commandLine
}

/// Whether the chosen engine can answer right now.
public enum AIReadiness: Equatable, Sendable {
    case ready
    /// The model is on its way; the text is the pill to show ("Getting ready… 40%"). Commands run when it lands.
    case preparing(String)
    /// Nothing will change on its own; the text says what to do.
    case unavailable(String)
}

public struct AIRequest: Sendable, Equatable {
    public var prompt: String
    /// Standing instructions ("Answer in plain text").
    public var system: String
    public var maxTokens: Int

    public init(prompt: String, system: String = "", maxTokens: Int = 1024) {
        self.prompt = prompt; self.system = system; self.maxTokens = maxTokens
    }
}

public enum AIError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case unavailable(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled: "Stopped"
        case .unavailable(let m), .failed(let m): m
        }
    }
}

/// An answer being generated; `cancel()` stops it and the completion reports `AIError.cancelled`.
public final class AIGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var onCancel: (@Sendable () -> Void)?

    public init() {}
    public var isCancelled: Bool { lock.withLock { cancelled } }

    public func cancel() {
        let action: (@Sendable () -> Void)? = lock.withLock {
            guard !cancelled else { return nil }
            cancelled = true
            defer { onCancel = nil }
            return onCancel
        }
        action?()
    }

    /// Sets what `cancel()` does (called at once if the generation was already cancelled).
    public func onCancel(_ action: @escaping @Sendable () -> Void) {
        let now: Bool = lock.withLock {
            if cancelled { return true }
            onCancel = action
            return false
        }
        if now { action() }
    }
}

@MainActor
public protocol AIServicing: AnyObject {
    var readiness: AIReadiness { get }
    /// Emits every change of `readiness` (on the main queue).
    var readinessChanges: AnyPublisher<AIReadiness, Never> { get }
    /// An AI command was just used: anything waiting for a quiet moment (the model download) starts now.
    func noteUsed()
    /// Answers `request` with the chosen engine. `onToken` gets each piece of the answer as it is generated and
    /// `completion` the whole answer, both on the main queue.
    func complete(_ request: AIRequest, onToken: @escaping @Sendable (String) -> Void,
                  completion: @escaping @Sendable (Result<String, AIError>) -> Void) -> AIGeneration
    /// Settings → AI.
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
    /// The AI engines behind `::ask` and friends (nil in a tool that doesn't load AIKit).
    public static var ai: AIServicing?
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
    /// Downloaded AI models (AIKit).
    public static var models: URL { ensure(support.appendingPathComponent("Models", isDirectory: true)) }
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
    /// Height of chrome resting over the bottom of the note (the always-shown slot bar); the end of a long note
    /// scrolls clear of it.
    var bottomOverlay: CGFloat { get set }
    /// While this returns a manager, Edit › Undo / Redo act on it instead of the note's own history (the shell's
    /// "Undo Delete Note" right after a note was deleted).
    var externalUndo: (() -> UndoManager?)? { get set }
}

@MainActor
public protocol EditorFactory: AnyObject {
    func makeEditor() -> NoteEditing
}
