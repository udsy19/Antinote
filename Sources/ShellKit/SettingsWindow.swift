import AppKit
import SwiftUI
import UniformTypeIdentifiers
import JotterCore

/// The Settings window: a sidebar of tabs (`SettingsTab`) with one SwiftUI form per tab.
@MainActor
final class SettingsWindow: NSObject {
    static let shared = SettingsWindow()

    final class Router: ObservableObject {
        @Published var tab: SettingsTab = .general
    }

    private let router = Router()
    private var window: NSWindow?

    func show(tab: SettingsTab?) {
        if let tab { router.tab = tab }
        let w = window ?? makeWindow()
        window = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        let hosting = NSHostingController(rootView: SettingsRoot(router: router))
        hosting.sizingOptions = []
        w.contentViewController = hosting
        w.title = "Jotter Settings"
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 780, height: 560))
        w.center()
        w.setFrameAutosaveName("JotterSettingsWindow")
        return w
    }
}

struct SettingsRoot: View {
    @ObservedObject var router: SettingsWindow.Router

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: Binding(get: { router.tab }, set: { if let t = $0 { router.tab = t } })) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            page(router.tab)
                .navigationTitle(router.tab.title)
        }
        .frame(minWidth: 680, minHeight: 460)
    }

    @ViewBuilder private func page(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettings()
        case .appearance: AppearanceSettings()
        case .writing: WritingSettings()
        case .lists: ListsSettings()
        case .math: MathSettings()
        case .copyPaste: CopyPasteSettings()
        case .keywords: KeywordsSettings()
        case .timers: TimersSettings()
        case .shortcuts: ShortcutsSettings()
        case .extensions: ExtensionsSettings()
        case .privacy: PrivacySettings()
        case .sync: SyncSettings()
        case .storage: StorageSettings()
        case .export: ExportSettings()
        case .about: AboutSettings()
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

// MARK: - Maintenance actions (Storage tab)

@MainActor
enum Maintenance {
    static func makeBackup() {
        do {
            let url = try Services.store.backup()
            HUD.show("Backup saved: \(url.deletingPathExtension().lastPathComponent)", symbol: "externaldrive.badge.checkmark")
        } catch {
            Alerts.error("The backup couldn't be made.", error)
        }
    }

    static func restore(_ backup: URL) {
        guard Alerts.confirm("Restore this backup?",
                             info: "Your notes will be replaced with “\(backup.deletingPathExtension().lastPathComponent)”. "
                                 + "Make a backup first if you might want today's notes back. Jotter quits; reopen it to finish.",
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
            HUD.show("All notes exported", symbol: "square.and.arrow.up")
        } catch {
            Alerts.error("The notes couldn't be exported.", error)
        }
    }

    /// Saves every note as one portable JSON file.
    static func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Jotter Notes.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Services.store.exportJSON().write(to: url, options: .atomic)
            HUD.show("Notes exported", symbol: "square.and.arrow.up")
        } catch {
            Alerts.error("The notes couldn't be saved.", error)
        }
    }

    /// Merges notes from a JSON export (newer edits win).
    static func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a Jotter notes export (.json)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try Services.store.importJSON(Data(contentsOf: url))
            HUD.show(count == 0 ? "No changes found" : "\(count) note\(count == 1 ? "" : "s") imported", symbol: "square.and.arrow.down")
        } catch {
            Alerts.error("Those notes couldn't be imported.", error)
        }
    }

    static func copySyncKey() {
        guard let key = Services.sync?.exportKey() else { HUD.show("No encryption key yet", symbol: "key"); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)
        HUD.show("Encryption key copied", symbol: "key.fill")
    }

    static func pasteSyncKey() {
        guard let text = Alerts.prompt(title: "Paste the encryption key from your other Mac"), !text.isEmpty else { return }
        do {
            try Services.sync?.importKey(text)
            HUD.show("Encryption key saved", symbol: "key.fill")
        } catch {
            Alerts.error("That key couldn't be used.", error)
        }
    }

    static func resetPreferences() {
        guard Alerts.confirm("Reset all preferences?", info: "Notes are kept. Jotter quits; reopen it to start with default settings.",
                             confirmTitle: "Reset and Quit", destructive: true) else { return }
        clearPreferences(keepOnboarding: true)
        NSApp.terminate(nil)
    }

    static func factoryReset() {
        guard Alerts.confirm("Reset Jotter to factory settings?",
                             info: "Every note — including The Void, archived and slotted notes — and every preference is deleted. "
                                 + "Backups stay in the backups folder. Jotter quits afterwards.",
                             confirmTitle: "Erase Everything", destructive: true) else { return }
        let store = Services.store!
        for note in store.deck + store.archived + store.void { store.deletePermanently(note.id) }
        clearPreferences(keepOnboarding: false)
        NSApp.terminate(nil)
    }

    private static func clearPreferences(keepOnboarding: Bool) {
        Defaults.store.removePersistentDomain(forName: JotterPaths.bundleID)
        if keepOnboarding { Defaults[.onboardingCompleted] = true }
        Defaults.store.synchronize()
    }
}
