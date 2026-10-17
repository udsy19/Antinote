import AppKit
import Combine
import ServiceManagement
import JotterCore

/// Where Jotter lives (Dock, status item, pseudo-menu-bar dropdown, nowhere), the global hotkey, pin on top
/// and launch at login.
@MainActor
final class Presence: NSObject {
    static let shared = Presence()

    private var statusItem: NSStatusItem?
    private var hotkeyToken: UInt32?
    private var cancellables: Set<AnyCancellable> = []
    private var shell: Shell { Shell.shared }

    var presence: AppPresence { Defaults[.appPresence] }
    var isDropdown: Bool { presence == .pseudoMenuBar }

    func start() {
        Defaults.publisher(.appPresence).dropFirst().sink { [weak self] _ in self?.presenceChanged() }.store(in: &cancellables)
        Defaults.publisher(.globalHotkey).sink { [weak self] in self?.registerHotkey($0) }.store(in: &cancellables)
        Defaults.publisher(.pinOnTop).sink { [weak self] _ in self?.applyLevel() }.store(in: &cancellables)
        Defaults.publisher(.launchAtLogin).sink { Self.applyLaunchAtLogin($0) }.store(in: &cancellables)
        updateStatusItem()
        applyFrameAutosave()
    }

    // MARK: Dock & status item

    func applyActivationPolicy() {
        switch presence {
        case .dock, .dockAndMenuBar: NSApp.setActivationPolicy(.regular)
        case .menuBar, .pseudoMenuBar, .hidden: NSApp.setActivationPolicy(.accessory)
        }
    }

    private func presenceChanged() {
        applyActivationPolicy()
        updateStatusItem()
        applyFrameAutosave()
        applyLevel()
        shell.showMain()
    }

    private func updateStatusItem() {
        let wanted = [.menuBar, .dockAndMenuBar, .pseudoMenuBar].contains(presence)
        if !wanted {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Jotter")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            let menu = NSMenu()
            menu.addItem(withTitle: "New Note", action: #selector(Shell.newNote(_:)), keyEquivalent: "").target = shell
            menu.addItem(withTitle: "Settings…", action: #selector(Shell.openSettings(_:)), keyEquivalent: "").target = shell
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Jotter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            statusItem?.menu = menu
            sender.performClick(nil)
            statusItem?.menu = nil
        } else {
            shell.toggleMain()
        }
    }

    /// Places the window right under the status item (pseudo-menu-bar mode).
    func positionDropdown(_ window: NSWindow) {
        guard isDropdown, let button = statusItem?.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.active
        var frame = window.frame
        frame.origin.x = min(max(anchor.midX - frame.width / 2, screen.visibleFrame.minX + 6),
                             screen.visibleFrame.maxX - frame.width - 6)
        frame.origin.y = anchor.minY - 4 - frame.height
        window.setFrame(frame, display: false)
    }

    private func applyFrameAutosave() {
        // The dropdown position must not overwrite the remembered free-floating frame.
        shell.window.setFrameAutosaveName(isDropdown ? "" : "JotterMainWindow")
    }

    // MARK: Level, hotkey, login item

    func applyLevel() {
        shell.window.level = Defaults[.pinOnTop] || isDropdown ? .floating : .normal
        shell.pinStateChanged()
    }

    private func registerHotkey(_ shortcut: Shortcut?) {
        if let hotkeyToken { HotkeyCenter.shared.unregister(hotkeyToken) }
        hotkeyToken = nil
        guard let shortcut else { return }
        hotkeyToken = HotkeyCenter.shared.register(shortcut) { [weak self] in self?.shell.toggleMain() }
        if hotkeyToken == nil {
            Log.app.error("Global hotkey \(shortcut.displayString, privacy: .public) is already in use")
        }
    }

    private static func applyLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled { try service.register() }
            if !enabled, service.status == .enabled { try service.unregister() }
        } catch {
            Log.app.error("Launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Whether losing focus should hide the main window.
    var hidesOnFocusLoss: Bool { isDropdown || (Defaults[.hideOnFocusLoss] && !Defaults[.pinOnTop]) }
}
