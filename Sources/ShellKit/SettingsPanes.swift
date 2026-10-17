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

struct GeneralSettings: View {
    @Default(.appPresence) private var presence
    @Default(.globalHotkey) private var hotkey
    @Default(.launchAtLogin) private var launchAtLogin
    @Default(.restorePinState) private var restorePin
    @Default(.hideOnFocusLoss) private var hideOnFocusLoss
    @Default(.syncPreferences) private var syncPreferences
    @Default(.syncExtensions) private var syncExtensions

    var body: some View {
        SettingsForm {
            Section("Window") {
                Captioned("Applies only while the window is unpinned.") {
                    Toggle("Hide Jotter when it loses focus", isOn: $hideOnFocusLoss)
                }
                Toggle("Restore pin state on open", isOn: $restorePin)
            }
            Section("Menu bar & Dock") {
                Picker("Show Jotter in", selection: $presence) {
                    ForEach(AppPresence.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if presence == .pseudoMenuBar {
                    Caption("Jotter drops down under its menu bar icon and hides when you click anywhere else.")
                }
                Toggle("Launch Jotter at login", isOn: $launchAtLogin)
            }
            Section("iCloud") {
                Captioned("Keeps settings, keywords, themes, and the global hotkey the same on your other Macs.") {
                    Toggle("Sync preferences with iCloud", isOn: $syncPreferences)
                }
                Toggle("Sync extensions with iCloud", isOn: $syncExtensions)
            }
            Section("Global Hotkey") {
                LabeledContent("Global Hotkey - Show Jotter") { ShortcutRecorder(shortcut: $hotkey).frame(width: 160) }
            }
        }
    }
}

// MARK: - Appearance

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
            Section("Color theme") {
                ThemeGrid(themes: themes, light: $lightTheme, dark: $darkTheme)
                Caption("Pick one theme for light mode (sun) and one for dark mode (moon). Custom themes are JSON files in the themes folder.")
                HStack {
                    Button("Reload Custom Themes") {
                        themes = Theme.all
                        NotificationCenter.default.post(name: Theme.didChange, object: nil)
                    }
                    Button("Open Themes Folder") { NSWorkspace.shared.open(JotterPaths.themes) }
                }
            }
            Section("Paper") {
                Picker("Paper", selection: $paperType) {
                    ForEach(PaperType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Opacity", selection: $paperOpacity) {
                    ForEach(PaperOpacity.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(paperType == .blank)
                if paperType == .blank { Caption("Select a non-blank paper type to enable opacity options.") }
            }
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
            Section("Window") {
                Captioned("Requires macOS 15 (Sequoia) or later.") {
                    Toggle("Make Jotter translucent", isOn: $translucent).disabled(!supportsTranslucency)
                }
            }
            Section("Bars") {
                Toggle("Show note modified/created time", isOn: $dates)
                Captioned("Marks the most recent note on the bottom right.") {
                    Toggle("Show latest-note indicator", isOn: $latestIndicator)
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
                Caption("Custom: any picture of your own, ideally square.")
            }
        }
    }
}

/// Every theme as a preview tile; the sun and moon buttons under a tile pick it for light or dark mode.
private struct ThemeGrid: View {
    let themes: [Theme]
    @Binding var light: String
    @Binding var dark: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 14) {
            ForEach(themes) { theme in
                let picked = light == theme.id || dark == theme.id
                VStack(spacing: 5) {
                    ThemePreview(theme: theme)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(picked ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: picked ? 2 : 1))
                    HStack(spacing: 6) {
                        Text(theme.name).font(.caption).lineLimit(1)
                        Spacer(minLength: 2)
                        pick("sun.max", "Use in light mode", selected: light == theme.id) { light = theme.id }
                        pick("moon", "Use in dark mode", selected: dark == theme.id) { dark = theme.id }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func pick(_ symbol: String, _ help: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button {
            action()
            NotificationCenter.default.post(name: Theme.didChange, object: nil)
        } label: {
            Image(systemName: selected ? symbol + ".fill" : symbol)
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// A miniature note in the theme's colours: keyword, a variable, a result and a short link.
private struct ThemePreview: View {
    let theme: Theme
    private func color(_ hex: String) -> Color { Color(nsColor: NSColor(hex: hex)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("math").foregroundStyle(color(theme.accent1Main))
            Text("cost").foregroundStyle(color(theme.accent1Secondary))
                + Text(":").foregroundStyle(color(theme.accent2Main))
                + Text(" 12").foregroundStyle(color(theme.typeMain))
            Text("cost").foregroundStyle(color(theme.accent1Tertiary))
                + Text(" * 4 = ").foregroundStyle(color(theme.typeMain))
                + Text("48.00").foregroundStyle(color(theme.accent3Main))
            Text("+site.io/...a1+").foregroundStyle(color(theme.typeSubtlePlus))
        }
        .font(.custom("Menlo", size: 9))
        .lineLimit(1)
        .padding(8)
        .frame(height: 70)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color(theme.background), in: RoundedRectangle(cornerRadius: 8))
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
    @Default(.swipeNavigation) private var swipe
    @Default(.swipeSensitivity) private var sensitivity

    private let families = NSFontManager.shared.availableFontFamilies

    var body: some View {
        SettingsForm {
            Section("Typography & language") {
                Caption("For non-English typography: pick a font that supports your language.")
                Picker("Font", selection: $fontName) {
                    Text("System Monospaced").tag("")
                    Divider()
                    ForEach(families, id: \.self) { Text($0).tag($0) }
                }
                Toggle("Force right-to-left (RTL) layout", isOn: $rtl)
                Button("Reset Font to Default") { Defaults.reset(.fontName); Defaults.reset(.forceRTL) }
            }
            Section("Links") {
                Captioned("Turning this off disables all link features.") {
                    Toggle("Detect and highlight links", isOn: $detectLinks)
                }
                Toggle("Shorten long links automatically", isOn: $shortenLinks).disabled(!detectLinks)
            }
            Section("Paste") {
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
            Section("Copy") {
                Toggle("Copy entire note when nothing is selected", isOn: $copyWhole)
                Toggle("Cut current line when nothing is selected", isOn: $cutLine)
                Toggle("Skip keyword when copying a whole note", isOn: $skipKeyword)
                Toggle("Copy list items as unchecked", isOn: $unchecked)
                Toggle("Skip checkboxes and bullets when copying", isOn: $skipMarkers)
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
            Section("Vim mode") {
                Captioned("Modal editing with Normal, Insert, and Visual modes. Press Escape to return to Normal mode.") {
                    Toggle("Vim mode", isOn: $vim)
                }
            }
            Section("Typing") {
                Toggle("Keep indentation of the previous line when pressing Return", isOn: $keepIndent)
                Toggle("Allow macOS text replacements", isOn: $replacements)
            }
            Section("Swiping") {
                Captioned("Swipe horizontally with two fingers to move to the previous or next note.") {
                    Toggle("Swipe between notes", isOn: $swipe)
                }
                Captioned("Higher values require more deliberate swipes.") {
                    Slider(value: $sensitivity, in: 0...1) { Text("Swipe sensitivity") }
                        minimumValueLabel: { Text("Light") } maximumValueLabel: { Text("Firm") }
                }
                .disabled(!swipe)
            }
        }
    }
}

// MARK: - Notes

struct NotesSettings: View {
    @Default(.syncNotes) private var syncNotes
    @Default(.syncPreferences) private var syncPreferences
    @Default(.syncExtensions) private var syncExtensions
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
            Section("iCloud") {
                Captioned("Notes are encrypted on this Mac before they're written to your iCloud Drive.") {
                    Toggle("Sync notes with iCloud", isOn: $syncNotes)
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
            Section("Automatic notes") {
                Captioned("Timer starts whenever the window loses focus. An empty latest note is reused.") {
                    Picker("Create a new note after", selection: $newNoteAfter) {
                        Text("Never").tag(0)
                        ForEach(Self.newNoteChoices, id: \.0) { Text($0.1).tag($0.0) }
                        if newNoteAfter != 0, !Self.newNoteChoices.contains(where: { $0.0 == newNoteAfter }) {
                            Text(minutesLabel(newNoteAfter)).tag(newNoteAfter)
                        }
                    }
                }
            }
            Section("The Void") {
                Captioned("Deleted notes are permanently removed after this period.") {
                    Picker("Auto-empty The Void after", selection: $retention) {
                        ForEach([1, 7, 30, 90], id: \.self) { Text("\($0) day\($0 == 1 ? "" : "s")").tag($0) }
                        Text("Never").tag(0)
                    }
                }
                LabeledContent {
                    Button("Recover Notes…") { Services.panels?.showVoid() }
                } label: {
                    Text("Recently deleted notes")
                    Text("Recover them, or erase them permanently.")
                }
            }
            Section("Slotted notes") {
                Toggle("Always show the slotted notes bar", isOn: $slotsBar)
                Captioned("Otherwise ⌘N on a slotted note only shows a reminder.") {
                    Toggle("Create new notes in the ephemeral pane when in slotted view", isOn: $newInEphemeral)
                }
                Toggle("Split horizontally", isOn: $splitHorizontal)
            }
            Section("Locked notes") {
                Captioned("Counted from the last time a locked note was in focus. Quitting Jotter always locks them.") {
                    Picker("Require Touch ID or password again after", selection: $relock) {
                        Text("Immediately").tag(0)
                        ForEach([1, 5, 15, 60], id: \.self) { Text(minutesLabel($0)).tag($0) }
                    }
                }
                LabeledContent("Relock locked notes") { Button("Relock") { Shell.shared.relockAll() } }
            }
            Section("Backups") {
                Captioned("Backups are timestamped copies stored next to your notes database. New backups overwrite the oldest one.") {
                    Stepper("Backups to keep: \(backupCount)", value: $backupCount, in: 1...50)
                }
                LabeledContent("Back up now") {
                    Button("Make Backup") { Maintenance.makeBackup(); backups = Services.store.backups }
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
                    Text("Restore From a Backup")
                    Text("Pick a backup. Jotter quits, and reopening it replaces your notes with the backup.")
                }
                LabeledContent("Notes & backups folder") {
                    Button("Open Folder") { NSWorkspace.shared.open(JotterPaths.support) }
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
    /// One group per keyword, in the reference's order.
    private static let order: [NoteMode] = [.sum, .average, .math, .list, .count, .code, .autopaste, .timer]

    var body: some View {
        SettingsForm {
            Section {
                Caption("Turn on a mode by typing one of its keywords on the first line of a note.")
            }
            ForEach(Self.order, id: \.self) { mode in
                Section(mode.defaultKeywords.first ?? mode.displayName) {
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
        Picker("Primary currency", selection: $primary) { ForEach(codes, id: \.self) { Text($0).tag($0) } }
        Picker("Secondary currency", selection: $secondary) { ForEach(codes, id: \.self) { Text($0).tag($0) } }
        Picker("Number of decimal points", selection: $decimals) {
            Text("Automatic").tag(-1)
            ForEach(0...7, id: \.self) { Text("\($0)").tag($0) }
        }
        Toggle("Show the primary currency symbol", isOn: $currencySymbol)
        Toggle("Use a thousands separator", isOn: $thousands)
        TextField(text: $answerWord, prompt: Text("ans")) {
            Text("Previous answer word")
            Text("`ans` and `prev` always refer to the previous result.")
        }
        Captioned(allowRates ? "" : "Fetching rates is turned off in Privacy settings.") {
            Toggle("Update currency rates daily", isOn: $autoUpdate).disabled(!allowRates)
        }
        Toggle("Prevent editing answers in math mode", isOn: $preventEditing)
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
                TextField("Code", text: $newCode).frame(width: 70)
                TextField("Rate", value: $newRate, format: .number)
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

    private var help: String {
        switch mode {
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
    }

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 4) {
                Text(help)
                Caption("Built in: " + mode.defaultKeywords.joined(separator: ", "))
            }
            TextField(text: $text, prompt: Text("None")) {
                Text("Additional keywords")
                Text("Separate each keyword with a comma")
            }
            .onSubmit(save)
            .onDisappear(perform: save)
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
            Section {
                Toggle("Pause timer when quitting the app", isOn: $pauseOnQuit)
                Toggle("Show time left in the menu bar", isOn: $inMenuBar)
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

struct ExportSettings: View {
    @Default(.exportDestinations) private var destinations
    @Default(.quickExportDestination) private var quick
    @Default(.omitKeywordInExport) private var omitKeyword
    @Default(.obsidianVault) private var vault

    var body: some View {
        SettingsForm {
            Section("Quick Export") {
                Captioned("Quick Export in the File menu sends the current note straight to this destination.") {
                    Picker("Quick Export destination", selection: $quick) {
                        Text("None").tag(ExportDestination?.none)
                        ForEach(ExportDestination.allCases.filter { destinations.contains($0) }, id: \.self) {
                            Text($0.displayName).tag(ExportDestination?.some($0))
                        }
                    }
                }
            }
            Section("Destinations") {
                ForEach(ExportDestination.allCases, id: \.self) { d in
                    Toggle(d.displayName, isOn: Binding(
                        get: { destinations.contains(d) },
                        set: { on in if on { destinations.insert(d) } else { destinations.remove(d) } }))
                }
                TextField("Obsidian vault", text: $vault, prompt: Text("Vault name"))
                    .disabled(!destinations.contains(.obsidian))
                Caption("Enabled destinations appear as export commands in the File menu.")
            }
            Section("Options") {
                Toggle("Omit keyword in exported notes", isOn: $omitKeyword)
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

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Enable extensions", isOn: $enabled)
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

struct PrivacySettings: View {
    @Default(.allowCurrencyRates) private var rates
    @Default(.allowExtensionUpdates) private var extensionUpdates
    @Default(.allowExtensionAPIs) private var extensionAPIs
    @Default(.syncNotes) private var syncNotes
    @Default(.syncPreferences) private var syncPreferences
    @Default(.syncExtensions) private var syncExtensions

    var body: some View {
        SettingsForm {
            Section("Allow these network calls") {
                Caption("Jotter works fully offline. Each switch below is the only way the feature next to it reaches the network.")
                row("Fetch currency conversion rates", "Calls open.er-api.com and api.coingecko.com.", $rates)
                row("Check GitHub for extension updates", "Calls github.com and raw.githubusercontent.com.", $extensionUpdates)
                row("Let extensions call their own APIs", "Only the web addresses each extension declares.", $extensionAPIs)
                row("Sync notes with iCloud", "Writes encrypted notes to your own iCloud Drive.", $syncNotes)
                row("Sync preferences with iCloud", "Writes encrypted settings to your own iCloud Drive.", $syncPreferences)
                row("Sync extensions with iCloud", "Copies your installed extensions to your own iCloud Drive.", $syncExtensions)
                Button("Turn Everything Off") {
                    for key in [Defaults.Keys.allowCurrencyRates, .allowExtensionUpdates, .allowExtensionAPIs,
                                .syncNotes, .syncPreferences, .syncExtensions] { Defaults[key] = false }
                }
            }
        }
    }

    private func row(_ title: String, _ detail: String, _ isOn: Binding<Bool>) -> some View {
        Captioned(detail) { Toggle(title, isOn: isOn) }
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
