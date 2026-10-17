import AppKit
import SwiftUI
import JotterCore

// One view per Settings tab. Every control reads and writes a `Defaults` key directly.

private func minutesLabel(_ m: Int) -> String {
    m < 60 ? "\(m) minute\(m == 1 ? "" : "s")" : "\(m / 60) hour\(m == 60 ? "" : "s")"
}

/// A control with a caption under it.
private struct Captioned<Control: View>: View {
    let caption: String
    @ViewBuilder let control: () -> Control
    init(_ caption: String, @ViewBuilder control: @escaping () -> Control) { self.caption = caption; self.control = control }
    var body: some View {
        VStack(alignment: .leading) {
            control()
            if !caption.isEmpty { Caption(caption) }
        }
    }
}

// MARK: - General

/// Section order follows the reference: iCloud, Startup, Menu bar & Dock, Window, Navigation.
struct GeneralSettings: View {
    @Default(.appPresence) private var presence
    @Default(.launchAtLogin) private var launchAtLogin
    @Default(.restorePinState) private var restorePin
    @Default(.hideOnFocusLoss) private var hideOnFocusLoss
    @Default(.swipeNavigation) private var swipe
    @Default(.swipeSensitivity) private var sensitivity

    var body: some View {
        SettingsForm {
            ICloudSection()
            Section("Startup") {
                Toggle("Launch Jotter at login", isOn: $launchAtLogin)
            }
            Section("Menu bar & Dock") {
                Picker("Show Jotter in", selection: $presence) {
                    ForEach(AppPresence.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if presence == .pseudoMenuBar {
                    Caption("Jotter drops down under its menu bar icon and hides when you click anywhere else.")
                }
            }
            Section("Window") {
                Captioned("Applies only while the window is unpinned.") {
                    Toggle("Hide Jotter when it loses focus", isOn: $hideOnFocusLoss)
                }
                Toggle("Restore pin state on open", isOn: $restorePin)
            }
            Section("Navigation") {
                Captioned("Swipe sideways on the trackpad to go to the previous or next note.") {
                    Toggle("Swipe between notes", isOn: $swipe)
                }
                LabeledContent {
                    HStack {
                        Slider(value: $sensitivity, in: 0...1).frame(width: 160)
                        Text("\(Int((sensitivity * 100).rounded()))%").monospacedDigit().frame(width: 50, alignment: .trailing)
                    }
                } label: {
                    Text("Swipe sensitivity")
                    Text("Higher values require more deliberate swipes.")
                }
                .disabled(!swipe)
            }
        }
    }
}

/// iCloud sync of notes and preferences, at the top of General like the reference.
private struct ICloudSection: View {
    @Default(.syncNotes) private var syncNotes
    @Default(.syncPreferences) private var syncPreferences
    @Default(.syncExtensions) private var syncExtensions

    var body: some View {
        Section("iCloud") {
            Captioned("Notes are encrypted on this Mac before they're written to your iCloud Drive.") {
                Toggle("Sync notes with iCloud", isOn: $syncNotes)
            }
            Captioned("Keeps settings, keywords, themes, and the global hotkey the same on your other Macs.") {
                Toggle("Sync preferences with iCloud", isOn: $syncPreferences)
            }
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                LabeledContent("Status") {
                    Text(Services.sync?.statusText ?? "Sync isn't available.").foregroundStyle(.secondary)
                }
            }
            Button("Sync Now") { Services.sync?.syncNow() }
                .disabled(!(syncNotes || syncPreferences || syncExtensions))
            Captioned("Your other Macs need the same key to read synced notes. It travels through iCloud Keychain when available; otherwise move it by hand.") {
                HStack {
                    Button("Copy Encryption Key") { Maintenance.copySyncKey() }
                    Button("Paste Key from Another Mac…") { Maintenance.pasteSyncKey() }
                }
            }
        }
    }
}

// MARK: - Appearance

/// Section order follows the reference: Text, Paper, Window, Bottom bar, Themes, App icon.
struct AppearanceSettings: View {
    @Default(.lightTheme) private var lightTheme
    @Default(.darkTheme) private var darkTheme
    @Default(.paperType) private var paperType
    @Default(.paperOpacity) private var paperOpacity
    @Default(.textSize) private var textSize
    @Default(.doubleFontSize) private var doubleFontSize
    @Default(.lineSpacing) private var lineSpacing
    @Default(.translucent) private var translucent
    @Default(.showNoteDates) private var dates
    @Default(.showLatestNoteIndicator) private var latestIndicator
    @Default(.appIcon) private var appIcon
    @State private var themes = Theme.all

    private var supportsTranslucency: Bool {
        if #available(macOS 15, *) { return true } else { return false }
    }

    var body: some View {
        SettingsForm {
            Section("Text") {
                Picker("Font size", selection: $textSize) {
                    ForEach(TextSize.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Double font size", isOn: $doubleFontSize)
                LabeledContent("Extra line spacing") {
                    HStack {
                        Slider(value: $lineSpacing, in: 0...16, step: 1)
                        Text("\(Int(lineSpacing)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }
            Section("Paper") {
                Picker("Paper type", selection: $paperType) {
                    ForEach(PaperType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Paper opacity", selection: $paperOpacity) {
                    ForEach(PaperOpacity.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(paperType == .blank)
                if paperType == .blank { Caption("Select a non-blank paper type to enable opacity options.") }
            }
            Section("Window") {
                Captioned("Requires macOS 15 (Sequoia) or later.") {
                    Toggle("Make Jotter translucent", isOn: $translucent).disabled(!supportsTranslucency)
                }
            }
            Section("Bottom bar") {
                Toggle("Show note modified/created time", isOn: $dates)
                Captioned("Marks the most recent note on the bottom right.") {
                    Toggle("Show latest-note indicator", isOn: $latestIndicator)
                }
            }
            Section("Themes") {
                ThemeGrid(themes: themes, light: $lightTheme, dark: $darkTheme)
                LabeledContent {
                    HStack {
                        Button("Reload") {
                            themes = Theme.all
                            NotificationCenter.default.post(name: Theme.didChange, object: nil)
                        }
                        Button("Open Folder") { NSWorkspace.shared.open(JotterPaths.themes) }
                    }
                } label: {
                    Text("Custom themes")
                    Text("Theme files are JSON, one per theme, in the themes folder.")
                }
            }
            Section("App icon") {
                HStack(spacing: 14) {
                    ForEach(AppIcons.styles) { style in
                        IconChoice(image: AppIcons.image(for: style, size: 128), name: style.name, selected: appIcon == style.id) {
                            AppIcons.select(style.id)
                        }
                    }
                    IconChoice(image: NSImage(contentsOf: AppIcons.customIconURL)
                               ?? NSImage(systemSymbolName: "photo.badge.plus", accessibilityDescription: nil) ?? NSImage(),
                               name: "Custom", selected: appIcon == AppIcons.customID) {
                        AppIcons.chooseCustomImage()
                    }
                }
                Caption("Custom: a PNG, JPEG or HEIC picture of your own. Square images look best.")
            }
        }
    }
}

/// The theme tiles, two to a row. Each tile shows the theme's name in the editor font over its background plus a
/// strip of its accent colours; the sun and moon badges in the corner pick it for light or dark mode.
private struct ThemeGrid: View {
    let themes: [Theme]
    @Binding var light: String
    @Binding var dark: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            (Text("Choose a ") + Text(Image(systemName: "sun.max.fill")) + Text(" light theme, and a ")
                + Text(Image(systemName: "moon.fill")) + Text(" dark theme."))
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], alignment: .leading,
                      spacing: 16) {
                ForEach(themes) { theme in
                    ThemeTile(theme: theme, isLight: light == theme.id, isDark: dark == theme.id,
                              pickLight: { pick { light = theme.id } }, pickDark: { pick { dark = theme.id } })
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func pick(_ change: () -> Void) {
        change()
        NotificationCenter.default.post(name: Theme.didChange, object: nil)
    }
}

/// One 250 × 100 pt theme tile.
private struct ThemeTile: View {
    let theme: Theme
    let isLight: Bool
    let isDark: Bool
    let pickLight: () -> Void
    let pickDark: () -> Void
    static let size = CGSize(width: 250, height: 100)

    private func color(_ hex: String) -> Color { Color(nsColor: NSColor(hex: hex)) }

    /// Accent swatches, left to right.
    private var swatches: [String] {
        [theme.accent1Main, theme.accent1Secondary, theme.accent1Tertiary, theme.accent2Main, theme.accent3Main,
         theme.accent4Main, theme.accent5Main, theme.typeHighlight]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(theme.name)
                .font(Font(Typography.font(size: 14)))
                .foregroundStyle(color(theme.typeMain))
                .lineLimit(1)
            HStack(spacing: 0) {
                ForEach(Array(swatches.enumerated()), id: \.offset) { _, hex in color(hex).frame(width: 24, height: 24) }
            }
        }
        .padding(8)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(color(theme.background), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(isLight || isDark ? Color.blue : Color.secondary.opacity(0.3), lineWidth: isLight || isDark ? 2 : 1))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                badge("sun.max.fill", .yellow, "Use in light mode", selected: isLight, pickLight)
                badge("moon.fill", .blue, "Use in dark mode", selected: isDark, pickDark)
            }
            .padding(.top, 7)
            .padding(.trailing, 10)
        }
    }

    private func badge(_ symbol: String, _ tint: Color, _ help: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(selected ? tint : Color.gray)
                .padding(6)
                .background(Color.black.opacity(selected ? 0.8 : 0.2), in: Circle())
                .overlay(Circle().stroke(selected ? Color.blue : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct IconChoice: View {
    let image: NSImage
    let name: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 52, height: 52)
                    .padding(3)
                    .background(selected ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 10))
                Text(name).font(.caption)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Editor

/// Section order follows the reference: Typing, Vim mode, Automatic lists, Copy, Clean up pasted text, Links,
/// then Typography & language.
struct EditorSettings: View {
    @Default(.fontName) private var fontName
    @Default(.forceRTL) private var rtl
    @Default(.detectLinks) private var detectLinks
    @Default(.shortenLinks) private var shortenLinks
    @Default(.cleanPaste) private var clean
    @Default(.pasteRemoveMarkdown) private var markdown
    @Default(.pasteRemoveBullets) private var bullets
    @Default(.pasteRemoveNumbering) private var numbering
    @Default(.pasteRemoveLeadingWhitespace) private var leading
    @Default(.pasteRemoveEmptyLines) private var emptyLines
    @Default(.copyWholeNoteWhenNoSelection) private var copyWhole
    @Default(.cutLineWhenNoSelection) private var cutLine
    @Default(.skipKeywordWhenCopying) private var skipKeyword
    @Default(.copyListItemsUnchecked) private var unchecked
    @Default(.skipListMarkersWhenCopying) private var skipMarkers
    @Default(.listContinuity) private var continuity
    @Default(.checkedItemBehavior) private var checked
    @Default(.vimMode) private var vim
    @Default(.keepIndentOnReturn) private var keepIndent
    @Default(.allowTextReplacements) private var replacements

    private let families = NSFontManager.shared.availableFontFamilies

    var body: some View {
        SettingsForm {
            Section("Typing") {
                Toggle("Keep indentation of the previous line when pressing Return", isOn: $keepIndent)
                Toggle("Allow macOS text replacements", isOn: $replacements)
            }
            Section("Vim mode") {
                Captioned("Modal editing with Normal, Insert, and Visual modes. Press Escape to return to Normal mode.") {
                    Toggle("Enable vim mode", isOn: $vim)
                }
            }
            Section("Automatic lists") {
                Captioned("Return on a list line starts the next item; Return on an empty item ends the list.") {
                    Toggle("Continue lists when pressing Return", isOn: $continuity)
                }
                Picker("When an item is checked", selection: $checked) {
                    Text("Stays in place").tag(CheckedItemBehavior.keep)
                    Text("Moves to the bottom").tag(CheckedItemBehavior.moveToBottom)
                    Text("Is deleted").tag(CheckedItemBehavior.delete)
                }
            }
            Section("Copy") {
                Captioned("⌘C with no selection copies the whole note.") {
                    Toggle("Copy entire note when nothing is selected", isOn: $copyWhole)
                }
                Captioned("⌘X with no selection cuts the line the cursor is on.") {
                    Toggle("Cut current line when nothing is selected", isOn: $cutLine)
                }
                Captioned("Copying only part of a note keeps the keyword (e.g. “math”).") {
                    Toggle("Skip keyword when copying a whole note", isOn: $skipKeyword)
                }
                Captioned("Checked items lose their checkmark in the copied text.") {
                    Toggle("Copy list items as unchecked", isOn: $unchecked)
                }
                Captioned("List markers are hidden in the note, so copied text can leave them out too.") {
                    Toggle("Skip checkboxes and bullets when copying", isOn: $skipMarkers)
                }
            }
            Section("Clean up pasted text") {
                Toggle("Clean up pasted text", isOn: $clean)
                Group {
                    Toggle("Remove leading spaces and tabs from new lines", isOn: $leading)
                    Toggle("Remove list numbering (1. 2. 3.)", isOn: $numbering)
                    Toggle("Remove list bullets", isOn: $bullets)
                    Toggle("Remove Markdown formatting", isOn: $markdown)
                    Toggle("Remove empty lines", isOn: $emptyLines)
                }
                .disabled(!clean)
                .padding(.leading, 16)
                Caption("Code and paste notes always keep pasted text as-is.")
            }
            Section("Links") {
                Captioned("Turning this off disables all link features.") {
                    Toggle("Detect and highlight links", isOn: $detectLinks)
                }
                Toggle("Shorten long links automatically", isOn: $shortenLinks).disabled(!detectLinks)
            }
            Section {
                Picker("Font", selection: $fontName) {
                    Text("System Monospaced").tag("")
                    Divider()
                    ForEach(families, id: \.self) { Text($0).tag($0) }
                }
                Toggle("Force right-to-left (RTL) layout", isOn: $rtl)
                Button("Reset Font to Default") { Defaults.reset(.fontName); Defaults.reset(.forceRTL) }
            } header: {
                Text("Typography & language (beta)")
            } footer: {
                Caption("For non-English typography: pick a font that supports your language.")
            }
        }
    }
}

// MARK: - Notes

/// Section order follows the reference: Automatic notes, Locked notes, The Void, Slotted notes, Backups, then
/// Jotter's import/export and Reset.
struct NotesSettings: View {
    @Default(.newNoteAfterMinutes) private var newNoteAfter
    @Default(.voidRetentionDays) private var retention
    @Default(.alwaysShowSlotsBar) private var slotsBar
    @Default(.shellKitNewNotesInEphemeral) private var newInEphemeral
    @Default(.shellKitSplitHorizontal) private var splitHorizontal
    @Default(.relockAfterMinutes) private var relock
    @Default(.backupCount) private var backupCount
    @State private var backups: [URL] = []

    /// "Create a new note after" choices, in minutes.
    private static let newNoteChoices: [(Int, String)] = [
        (10, "10 mins"), (180, "3 hrs"), (720, "12 hrs"), (4320, "3 days"), (10080, "1 week"), (43200, "1 month"),
    ]

    var body: some View {
        SettingsForm {
            Section("Automatic notes") {
                Picker(selection: $newNoteAfter) {
                    Text("Never").tag(0)
                    ForEach(Self.newNoteChoices, id: \.0) { Text($0.1).tag($0.0) }
                    if newNoteAfter != 0, !Self.newNoteChoices.contains(where: { $0.0 == newNoteAfter }) {
                        Text(minutesLabel(newNoteAfter)).tag(newNoteAfter)
                    }
                } label: {
                    Text("Create a new note after")
                    Text("Timer starts whenever the window loses focus. An empty latest note is reused.")
                }
            }
            Section("Locked notes") {
                Picker(selection: $relock) {
                    Text("Immediately").tag(0)
                    ForEach([1, 5, 15, 60], id: \.self) { Text(minutesLabel($0)).tag($0) }
                } label: {
                    Text("Require Touch ID or password again after")
                    Text("Counted from the last time a locked note was in focus. Quitting Jotter always locks them.")
                }
                LabeledContent {
                    Button("Relock Now") { Shell.shared.relockAll() }
                } label: {
                    Text("Relock locked notes")
                    Text("Asks for Touch ID or your password again on every locked note.")
                }
            }
            Section("The Void") {
                Picker(selection: $retention) {
                    ForEach([1, 7, 30, 90], id: \.self) { Text("\($0) day\($0 == 1 ? "" : "s")").tag($0) }
                    Text("Never").tag(0)
                } label: {
                    Text("Auto-empty The Void after")
                    Text("Deleted notes are permanently removed after this period.")
                }
                LabeledContent {
                    HStack {
                        Button("Recover Notes…") { Services.panels?.showVoid() }
                        Button("Empty The Void") { Services.panels?.emptyVoid() }
                    }
                } label: {
                    Text("Recently deleted notes")
                    Text("Recover them, or erase them permanently.")
                }
            }
            Section("Slotted notes") {
                Captioned("Otherwise ⌘N on a slotted note only shows a reminder.") {
                    Toggle("Create new notes in the ephemeral pane when in slotted view", isOn: $newInEphemeral)
                }
                Toggle("Split horizontally", isOn: $splitHorizontal)
                Toggle("Always show the slotted notes bar", isOn: $slotsBar)
            }
            Section("Backups") {
                LabeledContent {
                    Stepper(value: $backupCount, in: 1...50) {
                        Text("\(backupCount)").monospacedDigit().frame(width: 50, alignment: .trailing)
                    }
                } label: {
                    Text("Auto-backups to keep")
                    Text("New backups overwrite the oldest one.")
                }
                LabeledContent("Back up now") {
                    Button("Make Backup") { Maintenance.makeBackup(); backups = Services.store.backups }
                }
                LabeledContent {
                    Button("Open Folder") { NSWorkspace.shared.open(JotterPaths.support) }
                } label: {
                    Text("Notes & backups folder")
                    Text("Backups are timestamped copies stored next to your notes database.")
                }
                LabeledContent {
                    Menu("Choose…") {
                        if backups.isEmpty { Text("No backups yet") }
                        ForEach(backups, id: \.self) { url in
                            Button(url.deletingPathExtension().lastPathComponent) { Maintenance.restore(url) }
                        }
                    }
                    .fixedSize()
                } label: {
                    Text("Restore from a backup")
                    Text("Swaps your notes for a backup's. Jotter quits; open it again to finish.")
                }
            }
            Section("Import & export") {
                Captioned("JSON keeps everything (slots, locks, dates) and can be imported on another Mac.") {
                    HStack {
                        Button("Export as JSON…") { Maintenance.exportJSON() }
                        Button("Import JSON…") { Maintenance.importJSON() }
                    }
                }
            }
            Section("Reset") {
                HStack {
                    Button("Reset Preferences…") { Maintenance.resetPreferences() }
                    Button("Reset App to Factory Settings…", role: .destructive) { Maintenance.factoryReset() }
                }
            }
        }
        .onAppear { backups = Services.store?.backups ?? [] }
    }
}

// MARK: - Keywords

/// The keyword groups of Settings › Keywords, in the reference's order and with its short titles.
public enum KeywordGroups {
    public static let order: [NoteMode] = [.list, .math, .sum, .average, .count, .code, .timer, .autopaste]

    /// "List", "Math", "Sum", "Avg", "Count", "Code", "Timer"; AutoPaste is "Paste".
    public static func title(_ mode: NoteMode) -> String {
        switch mode {
        case .list: "List"
        case .average: "Avg"
        case .autopaste: "Paste"
        default: mode.displayName
        }
    }
}

/// One group per keyword (`KeywordGroups.order`).
struct KeywordsSettings: View {
    @Default(.primaryCurrency) private var primary
    @Default(.secondaryCurrency) private var secondary
    @Default(.decimalPlaces) private var decimals
    @Default(.showCurrencySymbol) private var currencySymbol
    @Default(.autoUpdateRates) private var autoUpdate
    @Default(.preventEditingAnswers) private var preventEditing
    @Default(.thousandsSeparator) private var thousands
    @Default(.answerWord) private var answerWord
    @Default(.customRates) private var rates
    @Default(.allowCurrencyRates) private var allowRates
    @Default(.defaultListStyle) private var listStyle
    @State private var newCode = ""
    @State private var newRate = 1.0

    private let codes = Locale.commonISOCurrencyCodes

    var body: some View {
        SettingsForm {
            ForEach(KeywordGroups.order, id: \.self) { mode in
                Section(KeywordGroups.title(mode)) {
                    KeywordRow(mode: mode)
                    if mode == .math { mathOptions }
                    if mode == .list {
                        Picker("Default list style", selection: $listStyle) {
                            Text("Checkboxes").tag(ListStyle.checkbox)
                            Text("Bullets").tag(ListStyle.bullet)
                            Text("Numbered").tag(ListStyle.numbered)
                        }
                    }
                }
                if mode == .math { customRatesSection }
            }
        }
    }

    @ViewBuilder private var mathOptions: some View {
        Picker("Significant digits", selection: $decimals) {
            Text("Automatic").tag(-1)
            ForEach(0...7, id: \.self) { Text("\($0)").tag($0) }
        }
        Toggle("Use a thousands separator", isOn: $thousands)
        TextField(text: $answerWord, prompt: Text("ans")) {
            Text("Previous answer word")
            Text("`ans` and `prev` always refer to the previous result.")
        }
        Captioned(allowRates ? "Calls open.er-api.com and api.coingecko.com." : "Fetching rates is turned off in Privacy settings.") {
            Toggle("Update currency rates daily", isOn: $autoUpdate).disabled(!allowRates)
        }
        Toggle("Prevent editing answers in math mode", isOn: $preventEditing)
        Toggle("Show the primary currency symbol", isOn: $currencySymbol)
        Picker("Primary currency", selection: $primary) { ForEach(codes, id: \.self) { Text($0).tag($0) } }
        Picker("Secondary currency", selection: $secondary) { ForEach(codes, id: \.self) { Text($0).tag($0) } }
    }

    private var customRatesSection: some View {
        Section("Custom currency rates") {
            Caption("These override live currency rates, and define currencies Jotter doesn't know. Enter units per 1 USD.")
            ForEach(rates.keys.sorted(), id: \.self) { code in
                HStack {
                    Text(code).monospaced().frame(width: 60, alignment: .leading)
                    TextField("Rate", value: Binding(get: { rates[code] ?? 0 }, set: { rates[code] = $0 }), format: .number)
                    Button(role: .destructive) { rates[code] = nil } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("Code", text: $newCode, prompt: Text("Code")).labelsHidden().frame(width: 70)
                TextField("Rate", value: $newRate, format: .number, prompt: Text("Rate")).labelsHidden()
                Button("Add") {
                    let code = newCode.trimmingCharacters(in: .whitespaces).uppercased()
                    guard !code.isEmpty, newRate > 0 else { return }
                    rates[code] = newRate
                    newCode = ""
                }
                .disabled(newCode.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

private struct KeywordRow: View {
    let mode: NoteMode
    @State private var text = ""

    /// What the keywords do, plus the reference's "Not case sensitive." note.
    static func help(_ mode: NoteMode) -> String {
        let what: String = switch mode {
        case .math: "Any of these will enable calculations in your note."
        case .sum: "Any of these will add up every number in your note."
        case .average: "Any of these will average every number in your note."
        case .count: "Any of these will count the lines, words and characters in your note."
        case .list: "Any of these will turn every line of your note into a checklist item."
        case .code: "Any of these will highlight your note as code."
        case .autopaste: "Any of these will collect everything you copy into your note."
        case .timer: "Any of these will start a timer from your note."
        case .plain: ""
        }
        return mode == .timer ? what : what + "\nNot case sensitive."
    }

    var body: some View {
        Group {
            LabeledContent("Built-in keywords") {
                Text(mode.defaultKeywords.joined(separator: ", ")).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                TextField(text: $text, prompt: Text("Additional keywords")) {
                    Text("Custom keywords")
                    Text(Self.help(mode))
                }
                .onSubmit(save)
                .onDisappear(perform: save)
                Caption("Separate each keyword with a comma. Press Return to save.")
            }
        }
        .onAppear { text = (Defaults[.extraKeywords][mode.rawValue] ?? []).joined(separator: ", ") }
    }

    private func save() {
        let words = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && !$0.contains(" ") && !mode.defaultKeywords.contains($0) }
        var all = Defaults[.extraKeywords]
        all[mode.rawValue] = words.isEmpty ? nil : words
        Defaults[.extraKeywords] = all
    }
}

// MARK: - Shortcuts

struct ShortcutsSettings: View {
    @Default(.globalHotkey) private var hotkey
    @Default(.shellKitSlotNumberShortcuts) private var slotShortcuts

    private var groups: [(String, [MainMenu.ShortcutEntry])] {
        var order: [String] = []
        var map: [String: [MainMenu.ShortcutEntry]] = [:]
        for e in MainMenu.shortcuts {
            if map[e.menu] == nil { order.append(e.menu) }
            map[e.menu, default: []].append(e)
        }
        return order.map { ($0, map[$0]!) }
    }

    var body: some View {
        SettingsForm {
            Section("Global") {
                Captioned("Works from any app. Click the field and press a combination; ⌫ clears it.") {
                    LabeledContent("Global Hotkey - Show Jotter") { ShortcutRecorder(shortcut: $hotkey).frame(width: 160) }
                }
                Captioned("While on, ⌘1 opens Slot 1 and every ⌘ + digit goes to a slot instead.") {
                    Toggle("⌘1–⌘9 jump to slotted notes", isOn: $slotShortcuts)
                }
            }
            ForEach(groups, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1) { entry in
                        LabeledContent(entry.title) { Text(entry.keys).monospaced().foregroundStyle(.secondary) }
                    }
                }
            }
            Section("Trackpad") {
                LabeledContent("Previous / next note") { Text("Two-finger swipe right / left").foregroundStyle(.secondary) }
            }
        }
    }
}

// MARK: - Timer

struct TimerSettings: View {
    @Default(.timerAlertStyle) private var alertStyle
    @Default(.timerSounds) private var sounds
    @Default(.timerInMenuBar) private var inMenuBar
    @Default(.pauseTimersOnQuit) private var pauseOnQuit
    @Default(.pomodoroWorkMinutes) private var work
    @Default(.pomodoroBreakMinutes) private var rest

    var body: some View {
        SettingsForm {
            Section("General") {
                Toggle("Pause timer when quitting the app", isOn: $pauseOnQuit)
                Captioned("Only when Jotter has a menu bar icon.") {
                    Toggle("Show time left in the menu bar", isOn: $inMenuBar)
                }
            }
            Section("When a countdown or pomodoro finishes") {
                Picker("Alert", selection: $alertStyle) {
                    Text("Show a full-screen alert").tag(TimerAlertStyle.fullScreen)
                    Text("Show a notification").tag(TimerAlertStyle.notification)
                    Text("Both").tag(TimerAlertStyle.both)
                }
                Toggle("Play a sound", isOn: $sounds)
            }
            Section("Pomodoro") {
                Stepper("Work: \(work) minutes", value: $work, in: 1...180)
                Stepper("Break: \(rest) minutes", value: $rest, in: 1...60)
                Caption("Used by “pomodoro” without numbers; “timer 50 10” sets both for one note.")
            }
        }
    }
}

// MARK: - Export

/// Section order follows the reference: Destinations, Quick Export, Options, then Export all notes.
struct ExportSettings: View {
    @Default(.exportDestinations) private var destinations
    @Default(.quickExportDestination) private var quick
    @Default(.omitKeywordInExport) private var omitKeyword
    @Default(.obsidianVault) private var vault

    var body: some View {
        SettingsForm {
            Section {
                ForEach(ExportDestination.allCases, id: \.self) { d in
                    Toggle(d.displayName, isOn: Binding(
                        get: { destinations.contains(d) },
                        set: { on in if on { destinations.insert(d) } else { destinations.remove(d) } }))
                    if d == .obsidian {
                        TextField(text: $vault, prompt: Text("Vault name")) {
                            Text("Obsidian vault")
                            Text("The vault's name from Obsidian's vault switcher, not a folder path.")
                        }
                        .disabled(!destinations.contains(.obsidian))
                        .padding(.leading, 16)
                    }
                }
            } header: {
                Text("Destinations")
            } footer: {
                Caption("Enabled destinations appear as export commands in the File menu.")
            }
            Section {
                Picker("Quick Export destination", selection: $quick) {
                    Text("None").tag(ExportDestination?.none)
                    ForEach(ExportDestination.allCases.filter { destinations.contains($0) }, id: \.self) {
                        Text($0.displayName).tag(ExportDestination?.some($0))
                    }
                }
            } header: {
                Text("Quick Export")
            } footer: {
                Caption("Quick Export in the File menu sends the current note straight to this destination.")
            }
            Section("Options") {
                Captioned("Leaves the keyword line (e.g. “math”) out of exported notes.") {
                    Toggle("Omit keyword in exported notes", isOn: $omitKeyword)
                }
            }
            Section {
                LabeledContent {
                    Button("Export All Notes…") { Maintenance.exportAll() }
                } label: {
                    Text("Export all notes")
                    Text("Saves every note as its own file in a folder you choose.")
                }
            }
        }
    }
}

// MARK: - Extensions

struct ExtensionsSettings: View {
    @Default(.extensionsEnabled) private var enabled
    @Default(.extensionLogging) private var logging
    @Default(.syncExtensions) private var syncExtensions

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Enable extensions", isOn: $enabled)
                if !enabled {
                    Label("Extensions are turned off. Turn them on above to use extension commands.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("iCloud Sync") {
                Toggle("Sync extensions with iCloud", isOn: $syncExtensions)
            }
            Section("Custom Extensions") {
                Captioned("Extension logs capture console output from JavaScript for debugging.") {
                    Toggle("Enable Extension Logging", isOn: $logging)
                }
            }
            Section("Loaded Extensions") {
                ExtensionsHost().frame(minHeight: 380)
            }
        }
    }
}

private struct ExtensionsHost: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        if let manager = Services.extensions { return manager.makeSettingsView() }
        return NSTextField(labelWithString: "Extensions aren't available.")
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

// MARK: - Privacy

/// The reference's layout: a "Network access" header with Turn Everything Off, then one group per area (iCloud
/// Sync, Features, Extensions) whose switch covers all its calls; "Advanced choices" lists each call on its own.
struct PrivacySettings: View {
    @Default(.allowCurrencyRates) private var rates
    @Default(.allowExtensionUpdates) private var extensionUpdates
    @Default(.allowExtensionAPIs) private var extensionAPIs
    @Default(.syncNotes) private var syncNotes
    @Default(.syncPreferences) private var syncPreferences
    @Default(.syncExtensions) private var syncExtensions

    private struct Call: Identifiable {
        let title: String
        let detail: String
        let endpoint: String
        let isOn: Binding<Bool>
        var id: String { title }
    }

    private var groups: [(title: String, subtitle: String, calls: [Call])] {
        [("iCloud Sync", "Calls to your own iCloud Drive to keep notes, settings and extensions in sync across your Macs.", [
            Call(title: "Sync notes with iCloud", detail: "Writes encrypted notes to your own iCloud Drive.",
                 endpoint: "iCloud Drive (Jotter folder)", isOn: $syncNotes),
            Call(title: "Sync preferences with iCloud", detail: "Writes encrypted settings to your own iCloud Drive.",
                 endpoint: "iCloud Drive (Jotter folder)", isOn: $syncPreferences),
            Call(title: "Sync extensions with iCloud", detail: "Copies your installed extensions to your own iCloud Drive.",
                 endpoint: "iCloud Drive (Jotter folder)", isOn: $syncExtensions),
         ]),
         ("Features", "Calls that keep currency conversion rates up to date.", [
            Call(title: "Fetch currency conversion rates", detail: "Custom rates in Keywords › Math work without it.",
                 endpoint: "open.er-api.com, api.coingecko.com", isOn: $rates),
         ]),
         ("Extensions", "Calls to find community extensions on GitHub, and the calls extensions make to their own services.", [
            Call(title: "Check GitHub for extension updates", detail: "Looks for new community extensions and updates.",
                 endpoint: "github.com, raw.githubusercontent.com", isOn: $extensionUpdates),
            Call(title: "Let extensions call their own APIs", detail: "Some extensions send note text to an outside service.",
                 endpoint: "Only the web addresses each extension declares", isOn: $extensionAPIs),
         ])]
    }

    var body: some View {
        SettingsForm {
            Section {
                LabeledContent {
                    Button("Turn Everything Off") {
                        for key in [Defaults.Keys.allowCurrencyRates, .allowExtensionUpdates, .allowExtensionAPIs,
                                    .syncNotes, .syncPreferences, .syncExtensions] { Defaults[key] = false }
                    }
                } label: {
                    Text("Network access")
                    Text("Every network call Jotter can make is listed below, and each one is yours to switch off. Jotter works fully offline.")
                }
            } footer: {
                Caption("Jotter doesn't collect usage data.")
            }
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    Toggle(sources: group.calls.map(\.isOn), isOn: \.self) {
                        Text("Allow these network calls")
                        Text(group.subtitle)
                    }
                    DisclosureGroup("Advanced choices") {
                        ForEach(group.calls) { call in
                            Toggle(isOn: call.isOn) {
                                Text(call.title)
                                Text(call.detail)
                                Text("Network call: " + call.endpoint)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Updates

struct UpdatesSettings: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "development build"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "Version \(short) (\($0))" } ?? "Version \(short)"
    }

    var body: some View {
        SettingsForm {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage ?? NSImage()).resizable().frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Jotter").font(.title2.bold())
                        Text(version).foregroundStyle(.secondary)
                        Text("A scratchpad for quick, disposable notes.").foregroundStyle(.secondary)
                    }
                }
                Caption("Jotter doesn't check for updates on its own.")
            }
            Section("License") {
                Text("Jotter is open source under the MIT License. Notes are plain text stored on this Mac.")
            }
            Section("Tutorial") {
                LabeledContent("Tutorial notes") { Button("Show Tutorial Notes") { Shell.shared.showTutorial(nil) } }
            }
        }
    }
}
