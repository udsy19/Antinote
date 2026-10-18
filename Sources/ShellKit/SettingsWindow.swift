import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SuperNotesCore

/// The Settings window: a standard toolbar-tab preferences window (`SettingsTab`) with one SwiftUI form per tab.
/// The window title follows the selected tab.
@MainActor
final class SettingsWindow: NSObject {
    static let shared = SettingsWindow()
    /// The reference sizes its tab view 800 × 500 pt.
    static let contentSize = NSSize(width: 800, height: 500)

    private var window: NSWindow?
    private var tabs: NSTabViewController?

    func show(tab: SettingsTab?) {
        let w = window ?? makeWindow()
        window = w
        if let tab { select(tab) }
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    private func select(_ tab: SettingsTab) {
        tabs?.selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: tab) ?? 0
    }

    private func makeWindow() -> NSWindow {
        let (w, controller) = Self.makeWindow(autosave: true)
        tabs = controller
        return w
    }

    /// A new, unshown Settings window (the app's own, or an offscreen one for previews).
    static func makeWindow(autosave: Bool) -> (NSWindow, NSTabViewController) {
        let controller = NSTabViewController()
        controller.tabStyle = .toolbar
        controller.transitionOptions = []
        for tab in SettingsTab.allCases {
            let hosting = NSHostingController(rootView: page(tab))
            hosting.title = tab.title
            hosting.sizingOptions = []
            hosting.preferredContentSize = contentSize
            let item = NSTabViewItem(viewController: hosting)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            item.identifier = tab.rawValue
            controller.addTabViewItem(item)
        }
        let w = NSWindow(contentViewController: controller)
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.toolbarStyle = .preference
        w.isReleasedWhenClosed = false
        if autosave {
            w.center()
            w.setFrameAutosaveName("SuperNotesSettingsWindow")   // restores the position
        }
        w.setContentSize(contentSize)
        return (w, controller)
    }

    @ViewBuilder static func page(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettings()
        case .appearance: AppearanceSettings()
        case .editor: EditorSettings()
        case .notes: NotesSettings()
        case .keywords: KeywordsSettings()
        case .shortcuts: ShortcutsSettings()
        case .timer: TimerSettings()
        case .export: ExportSettings()
        case .extensions: ExtensionsSettings()
        case .ai: AISettings()
        case .privacy: PrivacySettings()
        case .updates: UpdatesSettings()
        }
    }
}

/// A caption under a control.
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}

/// Grouped form used by every tab.
struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View { Form { content() }.formStyle(.grouped) }
}

// MARK: - Maintenance actions (Notes tab)

@MainActor
enum Maintenance {
    static func makeBackup() {
        do {
            let url = try Services.store.backup()
            HUD.show("Backup saved: \(url.deletingPathExtension().lastPathComponent)")
        } catch {
            Alerts.error("The backup couldn't be made.", error)
        }
    }

    static func restore(_ backup: URL) {
        guard Alerts.confirm("Restore this backup?",
                             info: "Your notes will be replaced with “\(backup.deletingPathExtension().lastPathComponent)”. "
                                 + "Make a backup first if you might want today's notes back. Super Notes quits; reopen it to finish.",
                             confirmTitle: "Restore and Quit", destructive: true) else { return }
        do {
            try Services.store.restore(from: backup)
            NSApp.terminate(nil)
        } catch {
            Alerts.error("The backup couldn't be restored.", error)
        }
    }

    static func exportAll() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for a copy of every note"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            try Services.export.exportAll(to: folder)
            HUD.show("All notes exported", kind: .success)
        } catch {
            Alerts.error("The notes couldn't be exported.", error)
        }
    }

    /// Saves every note as one portable JSON file.
    static func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Super Notes.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Services.store.exportJSON().write(to: url, options: .atomic)
            HUD.show("Notes exported", kind: .success)
        } catch {
            Alerts.error("The notes couldn't be saved.", error)
        }
    }

    /// Merges notes from a JSON export (newer edits win).
    static func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a Super Notes export (.json)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try Services.store.importJSON(Data(contentsOf: url))
            HUD.show(count == 0 ? "No changes found" : "\(count) note\(count == 1 ? "" : "s") imported")
        } catch {
            Alerts.error("Those notes couldn't be imported.", error)
        }
    }

    /// "Delete all notes not modified since": after confirming, sends every ephemeral, unarchived note last changed
    /// before that day to The Void.
    static func voidNotes(notModifiedSince date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        let notes = Services.store.deck.filter { $0.isUnmodified(since: day) }
        guard !notes.isEmpty else { HUD.show("No notes to delete before that date"); return }
        let count = "\(notes.count) note\(notes.count == 1 ? "" : "s")"
        guard Alerts.confirm("Move \(count) to The Void?",
                             info: "Every note not changed since \(day.formatted(date: .abbreviated, time: .omitted)) goes to "
                                 + "The Void. You can restore them from there until it is emptied.",
                             confirmTitle: "Move to The Void") else { return }
        for note in notes { Services.store.moveToVoid(note.id) }
        HUD.show("\(count) moved to The Void")
    }

    static func copySyncKey() {
        guard let key = Services.sync?.exportKey() else { HUD.show("No encryption key yet"); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)
        HUD.show("Encryption key copied")
    }

    static func pasteSyncKey() {
        guard let text = Alerts.prompt(title: "Paste the encryption key from your other Mac"), !text.isEmpty else { return }
        do {
            try Services.sync?.importKey(text)
            HUD.show("Encryption key saved")
        } catch {
            Alerts.error("That key couldn't be used.", error)
        }
    }

    static func resetPreferences() {
        guard Alerts.confirm("Reset all preferences?", info: "Notes are kept. Super Notes quits; reopen it to start with default settings.",
                             confirmTitle: "Reset and Quit", destructive: true) else { return }
        clearPreferences(keepOnboarding: true)
        NSApp.terminate(nil)
    }

    static func factoryReset() {
        guard Alerts.confirm("Reset Super Notes to factory settings?",
                             info: "Every note — including The Void, archived and slotted notes — and every preference is deleted. "
                                 + "Backups stay in the backups folder. Super Notes quits afterwards.",
                             confirmTitle: "Erase Everything", destructive: true) else { return }
        let store = Services.store!
        for note in store.deck + store.archived + store.void { store.deletePermanently(note.id) }
        clearPreferences(keepOnboarding: false)
        NSApp.terminate(nil)
    }

    private static func clearPreferences(keepOnboarding: Bool) {
        Defaults.store.removePersistentDomain(forName: SuperNotesPaths.bundleID)
        if keepOnboarding { Defaults[.onboardingCompleted] = true }
        Defaults.store.synchronize()
    }
}
