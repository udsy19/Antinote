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
        Defaults.changes.filter { $0 == Defaults.Keys.dropdownWidth.name || $0 == Defaults.Keys.dropdownHeight.name }
            .sink { [weak self] _ in
                guard let self, self.isDropdown, self.shell.window.isVisible else { return }
                self.positionDropdown(self.shell.window)
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: MenuBarTimer.didChange)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.showTimerText() } }.store(in: &cancellables)
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
        item.button?.image = AppIcons.menuBarIcon
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        statusItem = item
        showTimerText()
    }

    /// A running timer's time left sits next to the icon ("△ 04:37"); the item is square otherwise.
    private func showTimerText() {
        guard let statusItem else { return }
        let text = MenuBarTimer.text
        statusItem.button?.title = text.map { " " + $0 } ?? ""
        statusItem.length = text == nil ? NSStatusItem.squareLength : NSStatusItem.variableLength
    }

    /// Left click shows or hides Jotter; right click (or ⌃-click) opens the status menu.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem?.menu = statusMenu()
            sender.performClick(nil)
            statusItem?.menu = nil
        } else {
            shell.toggleMain()
        }
    }

    /// Settings, Create New Note, Export Note, Quit.
    func statusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings", action: #selector(Shell.openSettings(_:)), keyEquivalent: ",").target = shell
        menu.addItem(withTitle: "Create New Note", action: #selector(Shell.newNote(_:)), keyEquivalent: "n").target = shell
        let export = NSMenuItem(title: "Export Note", action: nil, keyEquivalent: "")
        export.submenu = MainMenu.exportMenu(target: shell)
        menu.addItem(export)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    /// Places the window right under the status item at the dropdown size (pseudo-menu-bar mode).
    func positionDropdown(_ window: NSWindow) {
        guard isDropdown, let button = statusItem?.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.active
        let size = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: Defaults[.dropdownWidth],
                                                           height: Defaults[.dropdownHeight])).size
        let frame = DropdownLayout.frame(size: size, minimum: window.minSize, anchor: anchor, visible: screen.visibleFrame)
        window.setFrame(frame, display: window.isVisible)
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
