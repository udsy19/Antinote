import AppKit
import SwiftUI
import JotterCore

// One view per Settings tab. Every control reads and writes a `Defaults` key directly.

private func minutesLabel(_ m: Int) -> String {
    m < 60 ? "\(m) minute\(m == 1 ? "" : "s")" : "\(m / 60) hour\(m == 60 ? "" : "s")"
}

// MARK: - General

struct GeneralSettings: View {
    @Default(.appPresence) private var presence
    @Default(.globalHotkey) private var hotkey
    @Default(.launchAtLogin) private var launchAtLogin
    @Default(.restorePinState) private var restorePin
    @Default(.hideOnFocusLoss) private var hideOnFocusLoss
    @Default(.newNoteAfterMinutes) private var newNoteAfter
    @Default(.swipeNavigation) private var swipe
    @Default(.swipeSensitivity) private var sensitivity
    @Default(.showLatestNoteIndicator) private var latestIndicator
    @Default(.showNoteDates) private var dates
    @Default(.forceRTL) private var rtl
    @Default(.alwaysShowSlotsBar) private var slotsBar
    @Default(.shellKitNewNotesInEphemeral) private var newInEphemeral
    @Default(.shellKitSplitHorizontal) private var splitHorizontal

    var body: some View {
        SettingsForm {
            Section("Window") {
                Picker("Show Jotter in", selection: $presence) {
                    ForEach(AppPresence.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if presence == .pseudoMenuBar {
                    Caption("Jotter drops down under its menu bar icon and hides when you click anywhere else.")
                }
                LabeledContent("Global hotkey") { ShortcutRecorder(shortcut: $hotkey) }
                Toggle("Launch Jotter at login", isOn: $launchAtLogin)
                Toggle("Restore pin state on open", isOn: $restorePin)
                VStack(alignment: .leading) {
                    Toggle("Hide Jotter when it loses focus", isOn: $hideOnFocusLoss)
                    Caption("Applies only while the window is unpinned.")
                }
            }
            Section("Notes") {
                Picker("Create a new note after", selection: $newNoteAfter) {
                    Text("Never").tag(0)
                    ForEach([5, 15, 30, 60, 120, 480], id: \.self) { Text(minutesLabel($0)).tag($0) }
                }
                Caption("Counted from when Jotter was last hidden. An empty latest note is reused.")
                VStack(alignment: .leading) {
                    Toggle("Show latest-note indicator", isOn: $latestIndicator)
                    Caption("Marks the most recent note on the bottom right.")
                }
                Toggle("Show note dates", isOn: $dates)
                Toggle("Force right-to-left (RTL) layout", isOn: $rtl)
            }
            Section("Swiping") {
                VStack(alignment: .leading) {
                    Toggle("Swipe between notes", isOn: $swipe)
                    Caption("Swipe horizontally with two fingers to move to the previous or next note.")
                }
                VStack(alignment: .leading) {
                    Slider(value: $sensitivity, in: 0...1) { Text("Swipe sensitivity") }
                        minimumValueLabel: { Text("Light") } maximumValueLabel: { Text("Firm") }
                    Caption("Higher values require more deliberate swipes.")
                }
                .disabled(!swipe)
            }
            Section("Slotted notes") {
                Toggle("Always show the slotted notes bar", isOn: $slotsBar)
                VStack(alignment: .leading) {
                    Toggle("Create new notes in the ephemeral pane when in slotted view", isOn: $newInEphemeral)
                    Caption("Otherwise ⌘N on a slotted note only shows a reminder.")
                }
                Toggle("Split horizontally", isOn: $splitHorizontal)
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
    @Default(.fontName) private var fontName
    @Default(.fontSize) private var fontSize
    @Default(.lineSpacing) private var lineSpacing
    @Default(.translucent) private var translucent
    @Default(.appIcon) private var appIcon

    private let themes = Theme.all
    private let families = NSFontManager.shared.availableFontFamilies
    private var supportsTranslucency: Bool {
        if #available(macOS 15, *) { return true } else { return false }
    }

    var body: some View {
        SettingsForm {
            Section("Light theme") {
                ThemeGrid(themes: themes.filter { !$0.isDark }, selection: $lightTheme)
                Caption("Used when macOS is in light mode. Custom themes are JSON files in the Themes folder.")
            }
            Section("Dark theme") {
                ThemeGrid(themes: themes.filter(\.isDark), selection: $darkTheme)
                Button("Open Themes Folder") { NSWorkspace.shared.open(JotterPaths.themes) }
            }
            Section("Paper") {
                Picker("Paper type", selection: $paperType) {
                    ForEach(PaperType.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                Slider(value: $paperOpacity, in: 0.1...1) { Text("Paper opacity") }
                    .disabled(paperType == .blank)
                if paperType == .blank { Caption("Select a non-blank paper type to enable opacity options.") }
            }
            Section("Text") {
                Picker("Font", selection: $fontName) {
                    Text("System Monospaced").tag("")
                    Divider()
                    ForEach(families, id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Size") {
                    HStack {
                        Slider(value: $fontSize, in: 10...32, step: 1)
                        Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                LabeledContent("Line spacing") {
                    HStack {
                        Slider(value: $lineSpacing, in: 0...16, step: 1)
                        Text("\(Int(lineSpacing))").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }
            Section("Window") {
                Toggle("Make Jotter translucent", isOn: $translucent).disabled(!supportsTranslucency)
                if !supportsTranslucency { Caption("Requires macOS 15 (Sequoia) or later.") }
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
                               name: "Your own", selected: appIcon == AppIcons.customID) {
                        AppIcons.chooseCustomImage()
                    }
                }
                Caption("An image of your own: any picture, ideally square.")
            }
        }
    }
}

private struct ThemeGrid: View {
    let themes: [Theme]
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 12)], spacing: 12) {
            ForEach(themes) { theme in
                Button {
                    selection = theme.id
                    NotificationCenter.default.post(name: Theme.didChange, object: nil)
                } label: {
                    VStack(spacing: 6) {
                        ThemePreview(theme: theme)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(selection == theme.id ? Color.accentColor : Color.secondary.opacity(0.3),
                                        lineWidth: selection == theme.id ? 2.5 : 1))
                        Text(theme.name).font(.caption)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ThemePreview: View {
    let theme: Theme
    private func color(_ hex: String) -> Color { Color(nsColor: NSColor(hex: hex)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("math").foregroundStyle(color(theme.secondaryText))
            HStack(spacing: 0) {
                Text("12 × 4").foregroundStyle(color(theme.text))
                Spacer(minLength: 4)
                Text("48").foregroundStyle(color(theme.result))
            }
            HStack(spacing: 4) {
                Circle().fill(color(theme.accent)).frame(width: 6, height: 6)
                Text("link").foregroundStyle(color(theme.link)).underline()
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(8)
        .frame(height: 64)
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

// MARK: - Writing, Lists, Math, Copy & Paste

struct WritingSettings: View {
    @Default(.vimMode) private var vim
    @Default(.keepIndentOnReturn) private var keepIndent
    @Default(.allowTextReplacements) private var replacements
    @Default(.detectLinks) private var detectLinks
    @Default(.shortenLinks) private var shortenLinks

    var body: some View {
        SettingsForm {
            Section("Editing") {
                VStack(alignment: .leading) {
                    Toggle("Vim mode", isOn: $vim)
                    Caption("Modal editing with Normal, Insert and Visual modes. Press Escape to return to Normal mode.")
                }
                Toggle("Keep indentation of the previous line when pressing Return", isOn: $keepIndent)
                Toggle("Allow macOS text replacements", isOn: $replacements)
            }
            Section("Links") {
                VStack(alignment: .leading) {
                    Toggle("Detect and highlight links", isOn: $detectLinks)
                    Caption("Turning this off disables all link features.")
                }
                Toggle("Shorten long links automatically", isOn: $shortenLinks).disabled(!detectLinks)
            }
        }
    }
}

struct ListsSettings: View {
    @Default(.defaultListStyle) private var style
    @Default(.checkedItemBehavior) private var checked
    @Default(.listContinuity) private var continuity

    var body: some View {
        SettingsForm {
            Section {
                Picker("Default list style", selection: $style) {
                    Text("Checkboxes").tag(ListStyle.checkbox)
                    Text("Bullets").tag(ListStyle.bullet)
                    Text("Numbers").tag(ListStyle.numbered)
                }
                Picker("When an item is checked", selection: $checked) {
                    Text("Keep it in place").tag(CheckedItemBehavior.keep)
                    Text("Move it to the bottom").tag(CheckedItemBehavior.moveToBottom)
                    Text("Delete it").tag(CheckedItemBehavior.delete)
                }
                VStack(alignment: .leading) {
                    Toggle("Inline list continuity on Return", isOn: $continuity)
                    Caption("Pressing Return on a list line starts the next item; Return on an empty item ends the list.")
                }
            }
        }
    }
}

struct MathSettings: View {
    @Default(.primaryCurrency) private var primary
    @Default(.secondaryCurrency) private var secondary
    @Default(.significantDigits) private var digits
    @Default(.autoUpdateRates) private var autoUpdate
    @Default(.preventEditingAnswers) private var preventEditing
    @Default(.thousandsSeparator) private var thousands
    @Default(.answerWord) private var answerWord
    @Default(.customRates) private var rates
    @Default(.allowCurrencyRates) private var allowRates
    @State private var newCode = ""
    @State private var newRate = 1.0

    private let codes = Locale.commonISOCurrencyCodes

    var body: some View {
        SettingsForm {
            Section("Currencies") {
                Picker("Primary currency", selection: $primary) { ForEach(codes, id: \.self) { Text($0).tag($0) } }
                Picker("Secondary currency", selection: $secondary) { ForEach(codes, id: \.self) { Text($0).tag($0) } }
                VStack(alignment: .leading) {
                    Toggle("Automatically update conversion rates daily", isOn: $autoUpdate).disabled(!allowRates)
                    if !allowRates { Caption("Fetching rates is turned off in Privacy settings.") }
                }
            }
            Section("Results") {
                Stepper("Significant digits: \(digits)", value: $digits, in: 1...15)
                Toggle("Prevent editing answers in math mode", isOn: $preventEditing)
                Toggle("Use a thousands separator", isOn: $thousands)
                TextField("Previous answer word", text: $answerWord)
                Caption("`ans` and `prev` always refer to the previous result.")
            }
            Section("Custom currency rates") {
                Caption("Units per 1 USD. These override fetched rates, and define currencies Jotter doesn't know.")
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
}

struct CopyPasteSettings: View {
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

    var body: some View {
        SettingsForm {
            Section("Paste") {
                Toggle("Clean up pasted text", isOn: $clean)
                Group {
                    Toggle("Remove Markdown formatting", isOn: $markdown)
                    Toggle("Remove list bullets", isOn: $bullets)
                    Toggle("Remove list numbering (1. 2. 3.)", isOn: $numbering)
                    Toggle("Remove leading spaces and tabs from new lines", isOn: $leading)
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
                VStack(alignment: .leading) {
                    Toggle("Copy list items as unchecked", isOn: $unchecked)
                    Caption("Checked items lose their checkmark in the copied text.")
                }
                Toggle("Skip checkboxes and bullets when copying", isOn: $skipMarkers)
            }
        }
    }
}

// MARK: - Keywords

struct KeywordsSettings: View {
    var body: some View {
        SettingsForm {
            Section {
                Caption("Activate a mode by typing one of its keywords on the first line. Add your own, separated by commas; press Return to save.")
            }
            ForEach(NoteMode.allCases.filter { $0 != .plain }, id: \.self) { mode in
                Section(mode.displayName) { KeywordRow(mode: mode) }
            }
        }
    }
}

private struct KeywordRow: View {
    let mode: NoteMode
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Built in: " + mode.defaultKeywords.joined(separator: ", ")).font(.callout).foregroundStyle(.secondary)
            TextField("Additional keywords", text: $text)
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

// MARK: - Timers

struct TimersSettings: View {
    @Default(.timerAlertStyle) private var alertStyle
    @Default(.timerSounds) private var sounds
    @Default(.timerInMenuBar) private var inMenuBar
    @Default(.pauseTimersOnQuit) private var pauseOnQuit
    @Default(.pomodoroWorkMinutes) private var work
    @Default(.pomodoroBreakMinutes) private var rest

    var body: some View {
        SettingsForm {
            Section("When a timer finishes") {
                Picker("Alert", selection: $alertStyle) {
                    Text("Show a full-screen alert").tag(TimerAlertStyle.fullScreen)
                    Text("Show a notification").tag(TimerAlertStyle.notification)
                    Text("Both").tag(TimerAlertStyle.both)
                }
                Toggle("Play sounds", isOn: $sounds)
            }
            Section("While running") {
                Toggle("Show time left in the menu bar", isOn: $inMenuBar)
                Toggle("Pause timer when quitting the app", isOn: $pauseOnQuit)
            }
            Section("Pomodoro") {
                Stepper("Work: \(work) minutes", value: $work, in: 1...180)
                Stepper("Break: \(rest) minutes", value: $rest, in: 1...60)
                Caption("Used by “pomodoro” without numbers; “timer 50 10” sets both for one note.")
            }
        }
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
                LabeledContent("Show or hide Jotter") { ShortcutRecorder(shortcut: $hotkey) }
                Caption("Works from any app. Click the field and press a combination; ⌫ clears it.")
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

// MARK: - Extensions

struct ExtensionsSettings: View {
    @Default(.extensionsEnabled) private var enabled
    @Default(.extensionLogging) private var logging

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Enable extensions", isOn: $enabled)
                VStack(alignment: .leading) {
                    Toggle("Enable extension logging", isOn: $logging)
                    Caption("Extension logs capture console output from JavaScript for debugging.")
                }
            }
            Section("Extension manager") {
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

// MARK: - Privacy & Sync

struct PrivacySettings: View {
    @Default(.allowCurrencyRates) private var rates
    @Default(.allowExtensionUpdates) private var extensionUpdates
    @Default(.allowExtensionAPIs) private var extensionAPIs
    @Default(.syncNotes) private var syncNotes
    @Default(.syncPreferences) private var syncPreferences
    @Default(.syncExtensions) private var syncExtensions
    @Default(.relockAfterMinutes) private var relock

    var body: some View {
        SettingsForm {
            Section("Allow these network calls") {
                Caption("Jotter works fully offline. Each switch below is the only way the feature next to it reaches the network.")
                row("Currency rates", "Fetches daily exchange rates for currency conversions in math notes.", $rates)
                row("Extension updates", "Checks the community extensions repository on GitHub for new extensions and updates.", $extensionUpdates)
                row("Extension APIs", "Lets extensions call their own web APIs (only the ones they declare).", $extensionAPIs)
                row("Sync notes", "Writes encrypted notes to your own iCloud Drive to keep your Macs in step.", $syncNotes)
                row("Sync preferences", "Keeps settings, keywords and themes the same on your other Macs via iCloud Drive.", $syncPreferences)
                row("Sync extensions", "Copies your installed extensions to your other Macs via iCloud Drive.", $syncExtensions)
                Button("Turn Everything Off") {
                    for key in [Defaults.Keys.allowCurrencyRates, .allowExtensionUpdates, .allowExtensionAPIs,
                                .syncNotes, .syncPreferences, .syncExtensions] { Defaults[key] = false }
                }
            }
            Section("Locked notes") {
                Picker("Require Touch ID or password again after", selection: $relock) {
                    Text("Immediately").tag(0)
                    ForEach([1, 5, 15, 60], id: \.self) { Text(minutesLabel($0)).tag($0) }
                }
                Caption("Counted from the last time a locked note was in focus. Quitting Jotter always locks them.")
                Button("Relock Locked Notes") { Shell.shared.relockAll() }
            }
        }
    }

    private func row(_ title: String, _ detail: String, _ isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading) {
            Toggle(title, isOn: isOn)
            Caption(detail)
        }
    }
}

struct SyncSettings: View {
    @Default(.syncNotes) private var syncNotes
    @Default(.syncPreferences) private var syncPreferences
    @Default(.syncExtensions) private var syncExtensions

    var body: some View {
        SettingsForm {
            Section("iCloud Drive") {
                Toggle("Sync notes", isOn: $syncNotes)
                Toggle("Sync preferences", isOn: $syncPreferences)
                Toggle("Sync extensions", isOn: $syncExtensions)
                Caption("Notes are encrypted on this Mac before they're written to iCloud Drive.")
            }
            Section("Status") {
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    Text(Services.sync?.statusText ?? "Sync isn't available.").foregroundStyle(.secondary)
                }
                Button("Sync Now") { Services.sync?.syncNow() }
                    .disabled(!(syncNotes || syncPreferences || syncExtensions))
            }
            Section("Encryption key") {
                Caption("Your other Macs need the same key to read synced notes. It travels through iCloud Keychain when available; otherwise move it by hand.")
                HStack {
                    Button("Copy Encryption Key") { Maintenance.copySyncKey() }
                    Button("Paste Key from Another Mac…") { Maintenance.pasteSyncKey() }
                }
            }
        }
    }
}

// MARK: - Storage

struct StorageSettings: View {
    @Default(.voidRetentionDays) private var retention
    @Default(.backupCount) private var backupCount
    @State private var backups: [URL] = []

    var body: some View {
        SettingsForm {
            Section("The Void") {
                Picker("Auto-empty The Void after", selection: $retention) {
                    ForEach([1, 7, 30, 90], id: \.self) { Text("\($0) day\($0 == 1 ? "" : "s")").tag($0) }
                    Text("Never").tag(0)
                }
                Caption("Deleted notes are permanently removed after this period.")
                Button("Recover Notes from The Void…") { Services.panels?.showVoid() }
            }
            Section("Backups") {
                Stepper("Backups to keep: \(backupCount)", value: $backupCount, in: 1...50)
                Caption("Backups are timestamped copies stored next to your notes database. New backups overwrite the oldest one.")
                HStack {
                    Button("Make Backup Now") { Maintenance.makeBackup(); backups = Services.store.backups }
                    Menu("Restore from a Backup") {
                        if backups.isEmpty { Text("No backups yet") }
                        ForEach(backups, id: \.self) { url in
                            Button(url.deletingPathExtension().lastPathComponent) { Maintenance.restore(url) }
                        }
                    }
                    .fixedSize()
                    Button("Open Folder") { NSWorkspace.shared.open(JotterPaths.backups) }
                }
            }
            Section("Export & import") {
                HStack {
                    Button("Export All Notes…") { Maintenance.exportAll() }
                    Button("Export as JSON…") { Maintenance.exportJSON() }
                    Button("Import JSON…") { Maintenance.importJSON() }
                }
                Caption("Export All Notes writes one file per note. JSON keeps everything (slots, locks, dates) and can be imported on another Mac.")
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

// MARK: - Export

struct ExportSettings: View {
    @Default(.exportDestinations) private var destinations
    @Default(.quickExportDestination) private var quick
    @Default(.omitKeywordInExport) private var omitKeyword
    @Default(.obsidianVault) private var vault

    var body: some View {
        SettingsForm {
            Section("Destinations") {
                ForEach(ExportDestination.allCases, id: \.self) { d in
                    Toggle(d.displayName, isOn: Binding(
                        get: { destinations.contains(d) },
                        set: { on in if on { destinations.insert(d) } else { destinations.remove(d) } }))
                }
                Caption("Enabled destinations appear as export commands in the File menu.")
            }
            Section("Quick Export") {
                Picker("Quick Export destination", selection: $quick) {
                    Text("None").tag(ExportDestination?.none)
                    ForEach(ExportDestination.allCases.filter { destinations.contains($0) }, id: \.self) {
                        Text($0.displayName).tag(ExportDestination?.some($0))
                    }
                }
                Caption("Quick Export (⇧⌘E) sends the current note straight to this destination.")
            }
            Section("Options") {
                Toggle("Omit keyword in exported notes", isOn: $omitKeyword)
                TextField("Obsidian vault", text: $vault, prompt: Text("Vault name"))
                    .disabled(!destinations.contains(.obsidian))
            }
        }
    }
}

// MARK: - About

struct AboutSettings: View {
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
            }
            Section("License") {
                Text("Jotter is open source under the MIT License. Notes are plain text stored on this Mac.")
            }
            Section {
                Button("Show Tutorial Notes") { Shell.shared.showTutorial(nil) }
            }
        }
    }
}
