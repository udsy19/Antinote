import AppKit
import SwiftUI
import SuperNotesCore

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
    @Default(.startWithNewNote) private var startWithNewNote
    @Default(.dropdownWidth) private var dropdownWidth
    @Default(.dropdownHeight) private var dropdownHeight
    @Default(.restorePinState) private var restorePin
    @Default(.hideOnFocusLoss) private var hideOnFocusLoss
    @Default(.swipeNavigation) private var swipe
    @Default(.swipeSensitivity) private var sensitivity

    var body: some View {
        SettingsForm {
            ICloudSection()
            Section("Startup") {
                Toggle("Launch Super Notes at login", isOn: $launchAtLogin)
                Captioned("Opening Super Notes starts on a fresh note; an empty latest note is reused.") {
                    Toggle("Start with a new note", isOn: $startWithNewNote)
                }
            }
            Section("Menu bar & Dock") {
                Picker("Show Super Notes in", selection: $presence) {
                    ForEach(AppPresence.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if presence == .pseudoMenuBar {
                    Caption("Super Notes drops down under its menu bar icon and hides when you click anywhere else.")
                }
                LabeledContent {
                    HStack(spacing: 6) {
                        TextField("Width", value: $dropdownWidth, format: .number).labelsHidden().frame(width: 72)
                        Text("×").foregroundStyle(.secondary)
                        TextField("Height", value: $dropdownHeight, format: .number).labelsHidden().frame(width: 72)
                    }
                } label: {
                    Text("Dropdown window size")
                    Text("Width × height in points while Super Notes drops down from the menu bar.")
                }
                .disabled(presence != .pseudoMenuBar)
            }
            Section("Window") {
                Captioned("Applies only while the window is unpinned.") {
                    Toggle("Hide Super Notes when it loses focus", isOn: $hideOnFocusLoss)
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
    @Default(.solidBarsWhenTranslucent) private var solidBars
    @Default(.translucencyOpacity) private var translucencyOpacity
    @Default(.showBottomBar) private var bottomBar
    @Default(.showNoteCount) private var noteCount
    @Default(.showNoteDates) private var dates
    @Default(.showCreationDate) private var creationDate
    @Default(.showLatestNoteIndicator) private var latestIndicator
    @Default(.slottedLightTheme) private var slottedLight
    @Default(.slottedDarkTheme) private var slottedDark
    @Default(.appIcon) private var appIcon
    @State private var themes = Theme.all
    /// Which pair the theme grid edits ("Applies to").
    @State private var themeTarget = ThemeTarget.ephemeral

    enum ThemeTarget: Hashable { case ephemeral, slotted }

    /// Slotted notes follow the ephemeral pair while neither slotted theme is set.
    private var slottedFollowsEphemeral: Binding<Bool> {
        Binding(get: { slottedLight.isEmpty && slottedDark.isEmpty }, set: { follow in
            if follow {
                slottedLight = ""; slottedDark = ""
            } else {
                slottedLight = lightTheme; slottedDark = darkTheme
            }
            NotificationCenter.default.post(name: Theme.didChange, object: nil)
        })
    }

    /// The light/dark pair the grid shows and changes.
    private func pair(dark: Bool) -> Binding<String> {
        Binding(get: {
            switch themeTarget {
            case .ephemeral: dark ? darkTheme : lightTheme
            case .slotted: Theme.selectedID(dark: dark, slotted: true)
            }
        }, set: { id in
            switch (themeTarget, dark) {
            case (.ephemeral, false): lightTheme = id
            case (.ephemeral, true): darkTheme = id
            case (.slotted, false): slottedLight = id
            case (.slotted, true): slottedDark = id
            }
        })
    }

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
                    Toggle("Make Super Notes translucent", isOn: $translucent).disabled(!supportsTranslucency)
                }
                Group {
                    Captioned("Otherwise the bars float on a blurred backdrop.") {
                        Toggle("Use solid colors for top and bottom bars when translucent", isOn: $solidBars)
                    }
                    LabeledContent {
                        HStack {
                            Slider(value: $translucencyOpacity, in: 0...1).frame(width: 180)
                            Text("\(Int((translucencyOpacity * 100).rounded()))%").monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    } label: {
                        Text("Translucency opacity")
                        Text("0% uses the most translucent macOS material.")
                    }
                }
                .disabled(!translucent || !supportsTranslucency)
            }
            Section("Bottom bar") {
                Toggle("Show bottom bar", isOn: $bottomBar)
                Group {
                    Captioned("e.g. “14 of 18”.") { Toggle("Show note count", isOn: $noteCount) }
                    Toggle("Show the time of day next to the date", isOn: $dates)
                    Toggle("Date the note by when it was created, not last changed", isOn: $creationDate)
                }
                .disabled(!bottomBar)
                Captioned("Marks the most recent note on the bottom right.") {
                    Toggle("Show latest-note indicator", isOn: $latestIndicator)
                }
            }
            Section("Themes") {
                Picker("Applies to", selection: $themeTarget) {
                    Text("Ephemeral").tag(ThemeTarget.ephemeral)
                    Text("Slotted").tag(ThemeTarget.slotted)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                if themeTarget == .slotted {
                    Toggle("Use the Ephemeral themes in Slotted too", isOn: slottedFollowsEphemeral)
                    if slottedFollowsEphemeral.wrappedValue {
                        Caption("Slotted notes follow the Ephemeral themes. Pick one below to give them their own.")
                    }
                }
                ThemeGrid(themes: themes, light: pair(dark: false), dark: pair(dark: true))
                LabeledContent {
                    HStack {
                        Button("Reload") {
                            themes = Theme.all
                            NotificationCenter.default.post(name: Theme.didChange, object: nil)
                        }
                        Button("Open Folder") { NSWorkspace.shared.open(SuperNotesPaths.themes) }
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
    @Default(.vimMotionTimeout) private var motionTimeout
    @Default(.keepIndentOnReturn) private var keepIndent
    @Default(.allowTextReplacements) private var replacements
    @Default(.checkSpelling) private var spelling
    @Default(.inlineCheckboxes) private var inlineCheckboxes
    @Default(.inlineBullets) private var inlineBullets
    @Default(.inlineNumbered) private var inlineNumbered
    @Default(.autoCopySelection) private var autoCopy
    @Default(.caretOffset) private var caretOffset
    @Default(.caretOffsetInLists) private var caretOffsetInLists

    private let families = NSFontManager.shared.availableFontFamilies

    var body: some View {
        SettingsForm {
            Section("Typing") {
                Toggle("Keep indentation of the previous line when pressing Return", isOn: $keepIndent)
                Toggle("Allow macOS text replacements", isOn: $replacements)
                Captioned("Code notes are never spell-checked.") {
                    Toggle("Check spelling", isOn: $spelling)
                }
            }
            Section("Vim mode") {
                Captioned("Modal editing with Normal, Insert, and Visual modes. Press Escape to return to Normal mode.") {
                    Toggle("Enable vim mode", isOn: $vim)
                }
                LabeledContent {
                    HStack {
                        Slider(value: $motionTimeout, in: 200...3000, step: 50).frame(width: 160)
                        Text(String(format: "%.0fms", motionTimeout)).monospacedDigit().frame(width: 64, alignment: .trailing)
                    }
                } label: {
                    Text("Motion timeout")
                    Text("How long to wait for the next key of a multi-key command such as “dd” or “2w”.")
                }
                .disabled(!vim)
            }
            Section("Automatic lists") {
                Captioned("Start a line with “[ ]” or “[x]”.") { Toggle("Checkboxes", isOn: $inlineCheckboxes) }
                Captioned("Start a line with “-”, “*” or “•”.") { Toggle("Bullets", isOn: $inlineBullets) }
                Captioned("Start a line with “1.”; items renumber themselves as the list changes.") {
                    Toggle("Numbered lists", isOn: $inlineNumbered)
                }
                Captioned("Return on a list line starts the next item; Return on an empty item ends the list.") {
                    Toggle("Continue lists when pressing Return", isOn: $continuity)
                }
                Picker(selection: $checked) {
                    Text("Stays in place").tag(CheckedItemBehavior.keep)
                    Text("Moves to the bottom").tag(CheckedItemBehavior.moveToBottom)
                    Text("Is deleted").tag(CheckedItemBehavior.delete)
                } label: {
                    Text("When an item is checked")
                    Text("Moving keeps the item inside its list. Both can be undone.")
                }
            }
            Section("Copy") {
                Captioned("Selecting text copies it right away. Quick, but it takes some getting used to.") {
                    Toggle("Auto-copy selected text", isOn: $autoCopy)
                }
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
                caretSlider("Caret height offset", value: $caretOffset)
                caretSlider("Caret height offset in lists", value: $caretOffsetInLists)
                Toggle("Force right-to-left (RTL) layout", isOn: $rtl)
                Button("Reset Font & Offsets to Defaults") {
                    for key in [Defaults.Keys.caretOffset, .caretOffsetInLists] { Defaults.reset(key) }
                    Defaults.reset(.fontName)
                    Defaults.reset(.forceRTL)
                }
            } header: {
                Text("Typography & language (beta)")
            } footer: {
                Caption("For non-English typography: pick a font that supports your language, and move the caret if it sits too high or too low.")
            }
        }
    }
}

extension EditorSettings {
    /// A −5…5 pt slider for the caret's height (positive raises it).
    private func caretSlider(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: -5...5, step: 0.5).frame(width: 160)
                Text(String(format: "%+.1f pt", value.wrappedValue)).monospacedDigit().frame(width: 64, alignment: .trailing)
            }
        }
    }
}

// MARK: - Notes

/// Section order follows the reference: Automatic notes, Locked notes, The Void, Slotted notes, Backups, then
/// Super Notes' import/export and Reset.
struct NotesSettings: View {
    @Default(.newNoteAfterMinutes) private var newNoteAfter
    @Default(.autoDeleteUnmodifiedDays) private var autoDeleteDays
    @Default(.showArchivedInStack) private var showArchived
    @Default(.voidRetentionDays) private var retention
    @Default(.alwaysShowSlotsBar) private var slotsBar
    @Default(.shellKitNewNotesInEphemeral) private var newInEphemeral
    @Default(.shellKitSplitHorizontal) private var splitHorizontal
    @Default(.slottedAsMain) private var slottedAsMain
    @Default(.relockAfterMinutes) private var relock
    @Default(.autoUnlockDelay) private var autoUnlock
    @Default(.backupCount) private var backupCount
    @Default(.backupIntervalHours) private var backupInterval
    @State private var backups: [URL] = []
    @State private var staleBefore = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()

    /// "Auto-delete unmodified notes after" choices, in days.
    private static let autoDeleteChoices: [(Int, String)] = [
        (1, "1 day"), (3, "3 days"), (7, "1 week"), (14, "2 weeks"), (30, "1 month"), (90, "3 months"), (365, "1 year"),
    ]
    /// "Backup interval" choices, in hours.
    private static let backupIntervals: [(Int, String)] = [
        (1, "Every hour"), (6, "Every 6 hours"), (12, "Every 12 hours"), (24, "Every day"), (168, "Every week"),
    ]

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
                Picker(selection: $autoDeleteDays) {
                    Text("Never").tag(0)
                    ForEach(Self.autoDeleteChoices, id: \.0) { Text($0.1).tag($0.0) }
                } label: {
                    Text("Auto-delete unmodified notes after")
                    Text("Notes you haven't changed in that long go to The Void. Slotted and archived notes stay.")
                }
                LabeledContent {
                    HStack {
                        DatePicker("Date", selection: $staleBefore, in: ...Date(), displayedComponents: .date).labelsHidden()
                        Button("Move to The Void") { Maintenance.voidNotes(notModifiedSince: staleBefore) }
                    }
                } label: {
                    Text("Delete all notes not modified since")
                    Text("You can bring them back from The Void until it is emptied.")
                }
            }
            Section("Archive") {
                Captioned("Archived notes stay out of search; search for “archived” to browse them.") {
                    Toggle("Show archived notes in the note stack", isOn: $showArchived)
                }
            }
            Section("Locked notes") {
                Picker(selection: $relock) {
                    Text("Immediately").tag(0)
                    ForEach([1, 5, 15, 60], id: \.self) { Text(minutesLabel($0)).tag($0) }
                } label: {
                    Text("Require Touch ID or password again after")
                    Text("Counted from the last time a locked note was in focus. Quitting Super Notes always locks them.")
                }
                Picker(selection: $autoUnlock) {
                    ForEach(AutoUnlock.choices, id: \.self) { delay in Text(Self.autoUnlockLabel(delay)).tag(delay) }
                } label: {
                    Text("Ask to unlock automatically")
                    Text("Staying on a locked note brings up Touch ID by itself; passing by quickly doesn't. “Never” waits for the Unlock button.")
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
                Captioned("Super Notes opens on your slotted notes instead of the ephemeral stack.") {
                    Toggle("Use slotted notes as your main notes", isOn: $slottedAsMain)
                }
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
                Picker("Backup interval", selection: $backupInterval) {
                    ForEach(Self.backupIntervals, id: \.0) { Text($0.1).tag($0.0) }
                    if !Self.backupIntervals.contains(where: { $0.0 == backupInterval }) {
                        Text("Every \(backupInterval) hours").tag(backupInterval)
                    }
                }
                LabeledContent("Back up now") {
                    Button("Make Backup") { Maintenance.makeBackup(); backups = Services.store.backups }
                }
                LabeledContent {
                    Button("Open Folder") { NSWorkspace.shared.open(SuperNotesPaths.support) }
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
                    Text("Swaps your notes for a backup's. Super Notes quits; open it again to finish.")
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

    static func autoUnlockLabel(_ delay: Double) -> String {
        switch delay {
        case ..<0: "Never"
        case 0: "Right away"
        default: delay < 1 ? String(format: "After %.1f seconds", delay) : "After \(Int(delay)) second\(delay == 1 ? "" : "s")"
        }
    }
}

// MARK: - Keywords

/// The keyword groups' short titles in Settings › Keywords (`NoteMode.keywordModes` gives their order).
public enum KeywordGroups {
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

/// One group per keyword (`NoteMode.keywordModes`).
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
    @Default(.keywordsEnabled) private var keywordsEnabled
    @State private var newCode = ""
    @State private var newRate = 1.0

    private let codes = Locale.commonISOCurrencyCodes

    var body: some View {
        SettingsForm {
            Section("General") {
                Captioned("Off: first lines never switch a note into math, a list, a timer or any other mode.") {
                    Toggle("Enable keywords", isOn: $keywordsEnabled)
                }
            }
            ForEach(NoteMode.keywordModes, id: \.self) { mode in
                Section(KeywordGroups.title(mode)) {
                    KeywordRow(mode: mode)
                    if mode == .math { mathOptions }
                    if mode == .list {
                        Picker(selection: $listStyle) {
                            Text("Checkboxes").tag(ListStyle.checkbox)
                            Text("Bullets").tag(ListStyle.bullet)
                            Text("Numbered").tag(ListStyle.numbered)
                        } label: {
                            Text("Default list style")
                            Text("What a plain line in a list note becomes. Checked lines always get a checkbox.")
                        }
                        CheckTriggersRow()
                    }
                }
                .disabled(!keywordsEnabled)
                if mode == .math { customRatesSection.disabled(!keywordsEnabled) }
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
            Caption("These override live currency rates, and define currencies Super Notes doesn't know. Enter units per 1 USD.")
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
    @Default(.mainKeywords) private var mainKeywords
    @Default(.extraKeywords) private var extraKeywords

    /// The main keyword picker's binding (`NoteMode.mainKeyword` falls back to the first keyword).
    private var main: Binding<String> {
        Binding(get: { mode.mainKeyword }, set: { mainKeywords[mode.rawValue] = $0 == mode.defaultKeywords.first ? nil : $0 })
    }

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
            Picker(selection: main) {
                ForEach(mode.defaultKeywords + (extraKeywords[mode.rawValue] ?? []), id: \.self) { Text($0).tag($0) }
            } label: {
                Text("Main keyword")
                Text("The one the “/” list and the command palette insert.")
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

/// "Check off items with": words that check off a list item when typed at its end.
private struct CheckTriggersRow: View {
    @Default(.checkTriggers) private var triggers
    @State private var text = ""

    var body: some View {
        TextField(text: $text, prompt: Text("/x")) {
            Text("Check off items with")
            Text("Type any of these at the end of a list item to check it off. Separate them with commas.")
        }
        .onSubmit(save)
        .onDisappear(perform: save)
        .onAppear { text = triggers.joined(separator: ", ") }
    }

    private func save() {
        triggers = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

// MARK: - Shortcuts

struct ShortcutsSettings: View {
    @Default(.globalHotkey) private var hotkey
    @Default(.shellKitSlotNumberShortcuts) private var slotShortcuts
    /// Read so the list redraws when a shortcut changes.
    @Default(.menuShortcuts) private var overrides

    private var groups: [(String, [MainMenu.ShortcutEntry])] {
        var order: [String] = []
        var map: [String: [MainMenu.ShortcutEntry]] = [:]
        for e in MainMenu.shortcuts {
            if map[e.menu] == nil { order.append(e.menu) }
            map[e.menu, default: []].append(e)
        }
        return order.map { ($0, map[$0]!) }
    }

    /// The recorder's binding: a new shortcut (or none) becomes the item's override.
    private func shortcut(_ entry: MainMenu.ShortcutEntry) -> Binding<Shortcut?> {
        Binding(get: { entry.shortcut }, set: { overrides[entry.id] = .some($0) })
    }

    var body: some View {
        SettingsForm {
            Section("Global") {
                Captioned("Works from any app. Click the field and press a combination; ⌫ clears it.") {
                    HStack {
                        Text("Global Hotkey - Show Super Notes")
                        Spacer()
                        ShortcutRecorder(shortcut: $hotkey).frame(width: 160, height: 24)
                    }
                }
                Captioned("While on, ⌘1 opens Slot 1 and every ⌘ + digit goes to a slot instead.") {
                    Toggle("⌘1–⌘9 jump to slotted notes", isOn: $slotShortcuts)
                }
                LabeledContent {
                    Button("Restore Defaults") { MainMenu.restoreDefaultShortcuts() }.disabled(overrides.isEmpty)
                } label: {
                    Text("Menu shortcuts")
                    Text("Click a shortcut below and press new keys; ⌫ removes it. Menus change right away.")
                }
            }
            ForEach(groups, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1) { entry in
                        HStack(spacing: 6) {
                            Text(entry.title)
                            Spacer()
                            ShortcutRecorder(shortcut: shortcut(entry), validator: { MainMenu.conflict($0, except: entry.id) })
                                .frame(width: 150, height: 24)
                            Button { overrides[entry.id] = nil } label: { Image(systemName: "arrow.uturn.backward") }
                                .buttonStyle(.borderless)
                                .help("Use the original shortcut")
                                .opacity(entry.isCustom ? 1 : 0)
                                .disabled(!entry.isCustom)
                        }
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
    @Default(.countdownNotification) private var countdownNotification
    @Default(.countdownFullScreen) private var countdownFullScreen
    @Default(.countdownSound) private var countdownSound
    @Default(.pomodoroNotification) private var pomodoroNotification
    @Default(.pomodoroFullScreen) private var pomodoroFullScreen
    @Default(.pomodoroSound) private var pomodoroSound
    @Default(.timerVolume) private var volume
    @Default(.timerInMenuBar) private var inMenuBar
    @Default(.pauseTimersOnQuit) private var pauseOnQuit
    @Default(.pomodoroWorkMinutes) private var work
    @Default(.pomodoroBreakMinutes) private var rest

    var body: some View {
        SettingsForm {
            Section("General") {
                Toggle("Pause timer when quitting the app", isOn: $pauseOnQuit)
                Captioned("Only when Super Notes has a menu bar icon.") {
                    Toggle("Show time left in the menu bar", isOn: $inMenuBar)
                }
            }
            Section("When a countdown finishes") {
                Toggle("Show a notification", isOn: $countdownNotification)
                Toggle("Show a full-screen alert", isOn: $countdownFullScreen)
                Toggle("Play a sound", isOn: $countdownSound)
            }
            Section {
                Toggle("Show a notification", isOn: $pomodoroNotification)
                Toggle("Show a full-screen alert", isOn: $pomodoroFullScreen)
                Toggle("Play a sound", isOn: $pomodoroSound)
            } header: {
                Text("When a pomodoro ends")
            } footer: {
                Caption("Applies to pomodoro sessions and breaks longer than 30 seconds.")
            }
            Section {
                LabeledContent("Volume") {
                    HStack {
                        Slider(value: $volume, in: 0...1).frame(width: 180)
                        Text("\(Int((volume * 100).rounded()))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                        Button("Test") { Services.timers?.playAlertSound() }
                    }
                }
            } header: {
                Text("Sound")
            } footer: {
                Caption("Affects both countdown and pomodoro alert sounds.")
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
    @Default(.exportFirstLineAsTitle) private var firstLineTitle
    @Default(.obsidianVault) private var vault
    @Default(.customURLTemplate) private var customURL

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
                    if d == .customURL {
                        TextField(text: $customURL, prompt: Text("myapp://create?title={TITLE}")) {
                            Text("URL")
                            Text("Sends notes to any app that accepts a URL scheme. Use {TITLE}, {CONTENT} and {DATE} as placeholders.")
                        }
                        .disabled(!destinations.contains(.customURL))
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
                Captioned("Otherwise notes are titled “Super Notes - ” and the date they were last changed.") {
                    Toggle("Use first line of note as title", isOn: $firstLineTitle)
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
    @Default(.installUpdates) private var installUpdates

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
                 endpoint: "iCloud Drive (Super Notes folder)", isOn: $syncNotes),
            Call(title: "Sync preferences with iCloud", detail: "Writes encrypted settings to your own iCloud Drive.",
                 endpoint: "iCloud Drive (Super Notes folder)", isOn: $syncPreferences),
            Call(title: "Sync extensions with iCloud", detail: "Copies your installed extensions to your own iCloud Drive.",
                 endpoint: "iCloud Drive (Super Notes folder)", isOn: $syncExtensions),
         ]),
         ("Features", "Calls that keep currency conversion rates up to date.", [
            Call(title: "Fetch currency conversion rates", detail: "Custom rates in Keywords › Math work without it.",
                 endpoint: "open.er-api.com, api.coingecko.com", isOn: $rates),
         ]),
         ("Updates", "Calls that keep Super Notes itself up to date.", [
            Call(title: "Install updates automatically",
                 detail: "Checks GitHub every few hours and installs new versions in the background.",
                 endpoint: "api.github.com, github.com (release downloads)", isOn: $installUpdates),
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
                                    .syncNotes, .syncPreferences, .syncExtensions, .installUpdates] { Defaults[key] = false }
                    }
                } label: {
                    Text("Network access")
                    Text("Every network call Super Notes can make is listed below, and each one is yours to switch off. Super Notes works fully offline.")
                }
            } footer: {
                Caption("Super Notes doesn't collect usage data.")
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
    @Default(.installUpdates) private var installUpdates
    @Default(.lastUpdateCheck) private var lastCheck

    private var updateStatus: String {
        guard installUpdates else { return "Automatic updates are turned off in Privacy settings." }
        guard lastCheck > 0 else { return "Not checked for updates yet." }
        return "Last checked " + Date(timeIntervalSince1970: lastCheck).formatted(date: .abbreviated, time: .shortened) + "."
    }

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
                        Text("Super Notes").font(.title2.bold())
                        Text(version).foregroundStyle(.secondary)
                        Text("A scratchpad for quick, disposable notes.").foregroundStyle(.secondary)
                    }
                }
                Caption(updateStatus)
            }
            Section("License") {
                Text("Super Notes is open source under the MIT License. Notes are plain text stored on this Mac.")
            }
            Section("Tutorial") {
                LabeledContent("Tutorial notes") { Button("Show Tutorial Notes") { Shell.shared.showTutorial(nil) } }
            }
        }
    }
}
