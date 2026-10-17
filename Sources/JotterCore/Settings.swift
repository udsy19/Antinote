import Foundation
import CoreGraphics

// All user-facing preferences, grouped by Settings tab. Module-private state may add keys in its own module
// (prefix the key name with the module).

public enum AppPresence: String, Codable, CaseIterable, Sendable {
    case dock, menuBar, dockAndMenuBar, pseudoMenuBar, hidden
    public var displayName: String {
        switch self {
        case .dock: "Dock"
        case .menuBar: "Menu bar"
        case .dockAndMenuBar: "Dock and menu bar"
        case .pseudoMenuBar: "Dropdown from the menu bar"
        case .hidden: "Nothing (global hotkey, Spotlight)"
        }
    }
}

public enum CheckedItemBehavior: String, Codable, CaseIterable, Sendable { case keep, moveToBottom, delete }
public enum ListStyle: String, Codable, CaseIterable, Sendable { case checkbox, bullet, numbered }
public enum PaperType: String, Codable, CaseIterable, Sendable {
    case blank, lines, dots, smallGrid, bigGrid
    public var displayName: String {
        switch self {
        case .blank: "Blank"
        case .lines: "Lines"
        case .dots: "Dots"
        case .smallGrid: "Small Grid"
        case .bigGrid: "Large grid"
        }
    }
}
/// Paper line strength; maps to the theme's `gridSuperlight` / `gridClear` / `gridBold`.
public enum PaperOpacity: String, Codable, CaseIterable, Sendable {
    case subtle, clear, bold
    public var displayName: String { rawValue.capitalized }
}
/// Editor text size presets (⌘+ / ⌘− step through them).
public enum TextSize: String, Codable, CaseIterable, Sendable {
    case xs, s, m, l, xl
    public var displayName: String { rawValue.uppercased() }
    public var points: CGFloat {
        switch self {
        case .xs: 10
        case .s: 12
        case .m: 14
        case .l: 16
        case .xl: 18
        }
    }
}
public enum ExportDestination: String, Codable, CaseIterable, Sendable {
    case appleNotes, obsidian, bear, plainText, markdown, pdf, customURL
    public var displayName: String {
        switch self {
        case .appleNotes: "Apple Notes"
        case .obsidian: "Obsidian"
        case .bear: "Bear"
        case .plainText: "Plain Text (.txt)"
        case .markdown: "Markdown (.md)"
        case .pdf: "PDF"
        case .customURL: "Custom URL scheme"
        }
    }
}

/// How long a locked note has to stay on screen before Touch ID is asked for on its own (Settings → Notes).
public enum AutoUnlock {
    /// Choices in seconds; `never` waits for the Unlock button.
    public static let never: Double = -1
    public static let choices: [Double] = [never, 0, 0.5, 1, 2]
}

public extension Defaults.Keys {
    // General / window
    static let appPresence = Key<AppPresence>("appPresence", default: .dockAndMenuBar)
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: false)
    static let globalHotkey = Key<Shortcut?>("globalHotkey", default: Shortcut(key: 0x00 /* A */, modifiers: [.option]))
    static let pinOnTop = Key<Bool>("pinOnTop", default: false)
    static let restorePinState = Key<Bool>("restorePinState", default: true)
    static let hideOnFocusLoss = Key<Bool>("hideOnFocusLoss", default: false)
    /// Minutes of inactivity after which showing Jotter starts a fresh note (0 = never).
    static let newNoteAfterMinutes = Key<Int>("newNoteAfterMinutes", default: 0)
    static let swipeNavigation = Key<Bool>("swipeNavigation", default: true)
    static let swipeSensitivity = Key<Double>("swipeSensitivity", default: 0)
    static let showLatestNoteIndicator = Key<Bool>("showLatestNoteIndicator", default: true)
    static let showNoteDates = Key<Bool>("showNoteDates", default: false)
    static let alwaysShowSlotsBar = Key<Bool>("alwaysShowSlotsBar", default: false)
    static let forceRTL = Key<Bool>("forceRTL", default: false)
    /// Launching Jotter opens on a fresh note (an empty front note is reused).
    static let startWithNewNote = Key<Bool>("startWithNewNote", default: false)
    /// Size of the window when it drops down from the menu bar (`AppPresence.pseudoMenuBar`).
    static let dropdownWidth = Key<Double>("dropdownWidth", default: 350)
    static let dropdownHeight = Key<Double>("dropdownHeight", default: 400)

    // Appearance
    static let lightTheme = Key<String>("lightTheme", default: Theme.defaultLight.id)
    static let darkTheme = Key<String>("darkTheme", default: Theme.defaultDark.id)
    static let paperType = Key<PaperType>("paperType", default: .blank)
    static let paperOpacity = Key<PaperOpacity>("paperOpacity", default: .subtle)
    static let fontName = Key<String>("fontName", default: "Menlo")
    static let textSize = Key<TextSize>("textSize", default: .m)
    static let doubleFontSize = Key<Bool>("doubleFontSize", default: false)
    /// Points added to the 1.6× line pitch.
    static let lineSpacing = Key<Double>("lineSpacing", default: 0)
    static let translucent = Key<Bool>("translucent", default: false)    // macOS 15+
    /// Translucent windows: the top and bottom bars get the theme background instead of a blurred material.
    static let solidBarsWhenTranslucent = Key<Bool>("solidBarsWhenTranslucent", default: false)
    /// Translucent windows: how much of the theme background covers the blur (0 = the most translucent).
    static let translucencyOpacity = Key<Double>("translucencyOpacity", default: 0.5)
    static let showBottomBar = Key<Bool>("showBottomBar", default: true)
    /// The bottom bar's "3 of 12".
    static let showNoteCount = Key<Bool>("showNoteCount", default: true)
    /// The bottom bar shows when the note was created instead of when it was last changed.
    static let showCreationDate = Key<Bool>("showCreationDate", default: false)
    /// Themes for slotted notes; empty follows `lightTheme` / `darkTheme`.
    static let slottedLightTheme = Key<String>("slottedLightTheme", default: "")
    static let slottedDarkTheme = Key<String>("slottedDarkTheme", default: "")
    static let appIcon = Key<String>("appIcon", default: "default")

    // Writing
    static let vimMode = Key<Bool>("vimMode", default: false)
    static let keepIndentOnReturn = Key<Bool>("keepIndentOnReturn", default: true)
    static let allowTextReplacements = Key<Bool>("allowTextReplacements", default: false)
    static let shortenLinks = Key<Bool>("shortenLinks", default: true)
    static let detectLinks = Key<Bool>("detectLinks", default: true)
    static let checkSpelling = Key<Bool>("checkSpelling", default: true)
    /// Milliseconds Vim mode waits for the next key of a multi-key command ("dd", "2w", "gg").
    static let vimMotionTimeout = Key<Double>("vimMotionTimeout", default: 1000)
    /// Selecting text copies it.
    static let autoCopySelection = Key<Bool>("autoCopySelection", default: false)
    /// Points the caret is raised (negative: lowered), in other notes and in list notes.
    static let caretOffset = Key<Double>("caretOffset", default: 0)
    static let caretOffsetInLists = Key<Double>("caretOffsetInLists", default: 0)

    // Lists
    /// What a plain line in a list note becomes, and where "Cycle List Type" starts.
    static let defaultListStyle = Key<ListStyle>("defaultListStyle", default: .checkbox)
    /// Which markers outside list notes become list items (drawn in the gutter, continued on Return).
    static let inlineCheckboxes = Key<Bool>("inlineCheckboxes", default: true)
    static let inlineBullets = Key<Bool>("inlineBullets", default: true)
    static let inlineNumbered = Key<Bool>("inlineNumbered", default: true)
    /// Typed at the end of a list item, any of these checks it off.
    static let checkTriggers = Key<[String]>("checkTriggers", default: ["/x"])
    static let checkedItemBehavior = Key<CheckedItemBehavior>("checkedItemBehavior", default: .keep)
    static let listContinuity = Key<Bool>("listContinuity", default: true)

    // Math
    static let primaryCurrency = Key<String>("primaryCurrency", default: Locale.current.currency?.identifier ?? "USD")
    static let secondaryCurrency = Key<String>("secondaryCurrency", default: "EUR")
    /// Decimal places shown in math results (0…7); -1 = automatic (up to 6 significant digits, zeros trimmed).
    static let decimalPlaces = Key<Int>("decimalPlaces", default: 2)
    /// Prefix results in the primary currency with its symbol ("$881.40" instead of "881.40").
    static let showCurrencySymbol = Key<Bool>("showCurrencySymbol", default: false)
    static let autoUpdateRates = Key<Bool>("autoUpdateRates", default: true)
    static let preventEditingAnswers = Key<Bool>("preventEditingAnswers", default: true)
    /// Word that refers to the previous answer in math notes; `ans` and `prev` always work.
    static let answerWord = Key<String>("answerWord", default: "ans")
    /// Group thousands in results.
    static let thousandsSeparator = Key<Bool>("thousandsSeparator", default: true)
    /// Exchange-rate overrides as units per 1 USD: ["XYZ": 2.5] means 1 USD = 2.5 XYZ.
    static let customRates = Key<[String: Double]>("customRates", default: [:])

    // Copy & paste
    static let cleanPaste = Key<Bool>("cleanPaste", default: true)
    static let pasteRemoveMarkdown = Key<Bool>("pasteRemoveMarkdown", default: true)
    static let pasteRemoveBullets = Key<Bool>("pasteRemoveBullets", default: true)
    static let pasteRemoveNumbering = Key<Bool>("pasteRemoveNumbering", default: true)
    static let pasteRemoveLeadingWhitespace = Key<Bool>("pasteRemoveLeadingWhitespace", default: true)
    static let pasteRemoveEmptyLines = Key<Bool>("pasteRemoveEmptyLines", default: false)
    static let copyWholeNoteWhenNoSelection = Key<Bool>("copyWholeNoteWhenNoSelection", default: true)
    static let cutLineWhenNoSelection = Key<Bool>("cutLineWhenNoSelection", default: true)
    static let skipKeywordWhenCopying = Key<Bool>("skipKeywordWhenCopying", default: true)
    static let copyListItemsUnchecked = Key<Bool>("copyListItemsUnchecked", default: false)
    static let skipListMarkersWhenCopying = Key<Bool>("skipListMarkersWhenCopying", default: false)

    // Keywords: extra keywords per NoteMode.rawValue
    static let extraKeywords = Key<[String: [String]]>("extraKeywords", default: [:])
    /// The keyword the "/" list and the palette insert, per NoteMode.rawValue (default: the first built-in one).
    static let mainKeywords = Key<[String: String]>("mainKeywords", default: [:])
    /// Off: first lines are never keywords (every note is plain text).
    static let keywordsEnabled = Key<Bool>("keywordsEnabled", default: true)

    // Timers
    static let countdownNotification = Key<Bool>("countdownNotification", default: false)
    static let countdownFullScreen = Key<Bool>("countdownFullScreen", default: true)
    static let countdownSound = Key<Bool>("countdownSound", default: true)
    static let pomodoroNotification = Key<Bool>("pomodoroNotification", default: false)
    static let pomodoroFullScreen = Key<Bool>("pomodoroFullScreen", default: true)
    static let pomodoroSound = Key<Bool>("pomodoroSound", default: true)
    /// Alert sound volume, 0…1.
    static let timerVolume = Key<Double>("timerVolume", default: 1)
    static let timerInMenuBar = Key<Bool>("timerInMenuBar", default: true)
    static let pauseTimersOnQuit = Key<Bool>("pauseTimersOnQuit", default: true)
    static let pomodoroWorkMinutes = Key<Int>("pomodoroWorkMinutes", default: 25)
    static let pomodoroBreakMinutes = Key<Int>("pomodoroBreakMinutes", default: 5)

    // Notes & storage
    static let voidRetentionDays = Key<Int>("voidRetentionDays", default: 30)   // 0 = keep forever
    static let backupCount = Key<Int>("backupCount", default: 5)
    /// Hours between automatic backups.
    static let backupIntervalHours = Key<Int>("backupIntervalHours", default: 24)
    /// Notes not changed for this many days move to The Void on their own (0 = never).
    static let autoDeleteUnmodifiedDays = Key<Int>("autoDeleteUnmodifiedDays", default: 0)
    /// Archived notes stay in the note stack, after the others.
    static let showArchivedInStack = Key<Bool>("showArchivedInStack", default: false)
    /// Seconds a locked note stays on screen before Touch ID is asked for (`AutoUnlock.never` = only on Unlock).
    static let autoUnlockDelay = Key<Double>("autoUnlockDelay", default: AutoUnlock.never)
    /// Jotter opens on the slotted notes instead of the ephemeral stack.
    static let slottedAsMain = Key<Bool>("slottedAsMain", default: false)
    static let relockAfterMinutes = Key<Int>("relockAfterMinutes", default: 5)
    static let exportDestinations = Key<Set<ExportDestination>>("exportDestinations", default: [.appleNotes, .markdown, .plainText, .pdf])
    static let quickExportDestination = Key<ExportDestination?>("quickExportDestination", default: nil)
    static let omitKeywordInExport = Key<Bool>("omitKeywordInExport", default: true)
    static let obsidianVault = Key<String>("obsidianVault", default: "")
    /// Exports are named after the note's first line; otherwise "Jotter - <last modified date>".
    static let exportFirstLineAsTitle = Key<Bool>("exportFirstLineAsTitle", default: true)
    /// The Custom URL scheme destination, with {TITLE}, {CONTENT} and {DATE} placeholders.
    static let customURLTemplate = Key<String>("customURLTemplate", default: "")

    // Privacy — every network-capable feature has its own switch
    static let allowCurrencyRates = Key<Bool>("allowCurrencyRates", default: true)
    static let allowExtensionUpdates = Key<Bool>("allowExtensionUpdates", default: false)
    static let allowExtensionAPIs = Key<Bool>("allowExtensionAPIs", default: false)
    static let syncNotes = Key<Bool>("syncNotes", default: false)
    static let syncPreferences = Key<Bool>("syncPreferences", default: false)
    static let syncExtensions = Key<Bool>("syncExtensions", default: false)

    // Extensions
    static let extensionsEnabled = Key<Bool>("extensionsEnabled", default: true)
    static let extensionLogging = Key<Bool>("extensionLogging", default: false)

    // Shortcuts
    /// Rebound menu shortcuts by menu item id (`MenuLogic.bindingID`); a nil value removes the item's shortcut.
    static let menuShortcuts = Key<[String: Shortcut?]>("menuShortcuts", default: [:])

    // Misc
    /// Alert IDs the user ticked "Don't ask again" for (reset in Settings → Advanced).
    static let suppressedWarnings = Key<Set<String>>("suppressedWarnings", default: [])
    static let onboardingCompleted = Key<Bool>("onboardingCompleted", default: false)
}
