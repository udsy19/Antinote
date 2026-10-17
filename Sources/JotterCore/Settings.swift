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
        case .xs: 11
        case .s: 12.5
        case .m: 13.5
        case .l: 16
        case .xl: 18
        }
    }
}
public enum TimerAlertStyle: String, Codable, CaseIterable, Sendable { case fullScreen, notification, both }
public enum ExportDestination: String, Codable, CaseIterable, Sendable {
    case appleNotes, obsidian, bear, plainText, markdown, pdf
    public var displayName: String {
        switch self {
        case .appleNotes: "Apple Notes"
        case .obsidian: "Obsidian"
        case .bear: "Bear"
        case .plainText: "Plain Text (.txt)"
        case .markdown: "Markdown (.md)"
        case .pdf: "PDF"
        }
    }
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
    static let swipeSensitivity = Key<Double>("swipeSensitivity", default: 0.5)
    static let showLatestNoteIndicator = Key<Bool>("showLatestNoteIndicator", default: true)
    static let showNoteDates = Key<Bool>("showNoteDates", default: false)
    static let alwaysShowSlotsBar = Key<Bool>("alwaysShowSlotsBar", default: false)
    static let forceRTL = Key<Bool>("forceRTL", default: false)

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
    static let appIcon = Key<String>("appIcon", default: "default")

    // Writing
    static let vimMode = Key<Bool>("vimMode", default: false)
    static let keepIndentOnReturn = Key<Bool>("keepIndentOnReturn", default: true)
    static let allowTextReplacements = Key<Bool>("allowTextReplacements", default: false)
    static let shortenLinks = Key<Bool>("shortenLinks", default: true)
    static let detectLinks = Key<Bool>("detectLinks", default: true)

    // Lists
    static let defaultListStyle = Key<ListStyle>("defaultListStyle", default: .checkbox)
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

    // Timers
    static let timerAlertStyle = Key<TimerAlertStyle>("timerAlertStyle", default: .fullScreen)
    static let timerSounds = Key<Bool>("timerSounds", default: true)
    static let timerInMenuBar = Key<Bool>("timerInMenuBar", default: true)
    static let pauseTimersOnQuit = Key<Bool>("pauseTimersOnQuit", default: true)
    static let pomodoroWorkMinutes = Key<Int>("pomodoroWorkMinutes", default: 25)
    static let pomodoroBreakMinutes = Key<Int>("pomodoroBreakMinutes", default: 5)

    // Notes & storage
    static let voidRetentionDays = Key<Int>("voidRetentionDays", default: 30)   // 0 = keep forever
    static let backupCount = Key<Int>("backupCount", default: 5)
    static let relockAfterMinutes = Key<Int>("relockAfterMinutes", default: 5)
    static let exportDestinations = Key<Set<ExportDestination>>("exportDestinations", default: [.appleNotes, .markdown, .plainText, .pdf])
    static let quickExportDestination = Key<ExportDestination?>("quickExportDestination", default: nil)
    static let omitKeywordInExport = Key<Bool>("omitKeywordInExport", default: true)
    static let obsidianVault = Key<String>("obsidianVault", default: "")

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

    // Misc
    /// Alert IDs the user ticked "Don't ask again" for (reset in Settings → Advanced).
    static let suppressedWarnings = Key<Set<String>>("suppressedWarnings", default: [])
    static let onboardingCompleted = Key<Bool>("onboardingCompleted", default: false)
}
