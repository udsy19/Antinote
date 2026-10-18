import AppKit
import Combine
import SuperNotesCore

extension Defaults.Keys {
    /// ⌘1…⌘9 open the slotted notes (and ⌘1 stops meaning Jump to Front). Off by default.
    static let shellKitSlotNumberShortcuts = Key<Bool>("shellKitSlotNumberShortcuts", default: false)
}

/// Builds the menu bar: the app menu, File, Edit, Appearance, Navigate, Support, Window and Help. Every item with a
/// key equivalent shows up in `shortcuts`, which Settings → Shortcuts lists and rebinds — the menu is the single
/// source of truth for keyboard shortcuts, and rebinding changes the menu items themselves
/// (`Defaults[.menuShortcuts]`).
@MainActor
enum MainMenu {
    struct ShortcutEntry: Identifiable {
        let menu: String
        let title: String
        let keys: String
        /// `MenuLogic.bindingID` of the item.
        let id: String
        /// The current shortcut, for the recorder (nil when the item has none).
        let shortcut: Shortcut?
        /// Rebound in Settings (not the built-in shortcut).
        let isCustom: Bool
    }

    /// Items whose title or visibility follows app state (pin, read-only, archive, lock, slot shortcuts).
    private static let state = MenuState()
    /// The menus once built (installed as the main menu in the app; only built in offscreen renders).
    private(set) static var built: NSMenu?
    /// File › Export Note › Quick Export: one lasting item, so its shortcut can be rebound like the others.
    private static var quickExportItem: NSMenuItem?

    /// The rebindable items and their active shortcuts, menu by menu, in menu order (hidden items are skipped).
    /// Items whose shortcut was removed are listed too, so one can be added back.
    static var shortcuts: [ShortcutEntry] {
        guard let built else { return [] }
        let overrides = Defaults[.menuShortcuts]
        var entries: [ShortcutEntry] = []
        func walk(_ menu: NSMenu, section: String) {
            menu.delegate?.menuNeedsUpdate?(menu)   // fills lazily built menus (Export Note)
            for item in menu.items where !item.isHidden && !item.isSeparatorItem {
                if let sub = item.submenu { walk(sub, section: section) }
                guard let binding = state.bindings.first(where: { $0.item === item }) else { continue }
                let key = item.keyEquivalent, mods = item.keyEquivalentModifierMask
                entries.append(ShortcutEntry(menu: section, title: item.title, keys: key.isEmpty ? "" : MenuLogic.display(key, mods),
                                             id: binding.id, shortcut: key.isEmpty ? nil : Shortcut(keyEquivalent: key, modifiers: mods),
                                             isCustom: overrides[binding.id] != nil))
            }
        }
        for top in built.items { if let sub = top.submenu { walk(sub, section: top.title) } }
        return entries
    }

    /// Why `shortcut` can't be used for the item `id`: it already belongs to another menu item.
    static func conflict(_ shortcut: Shortcut, except id: String) -> String? {
        let key = shortcut.keyEquivalent.lowercased(), mods = shortcut.modifiers.intersection(MenuLogic.bindingModifiers)
        guard let owner = state.bindings.first(where: { b in
            b.id != id && !b.item.keyEquivalent.isEmpty && b.item.keyEquivalent.lowercased() == key
                && b.item.keyEquivalentModifierMask.intersection(MenuLogic.bindingModifiers) == mods
        }) else { return nil }
        return "\(shortcut.displayString) is already used by “\(owner.item.title)”."
    }

    /// Builds the menus without installing them, so Settings → Shortcuts has rows in offscreen renders.
    static func buildForPreview() {
        if built == nil { _ = build(target: Shell.shared) }
    }

    /// Puts every rebindable item back on its built-in shortcut.
    static func restoreDefaultShortcuts() { Defaults[.menuShortcuts] = [:] }

    private static let up = MenuLogic.upArrow
    private static let down = MenuLogic.downArrow

    static func build(target shell: Shell) -> NSMenu {
        let main = NSMenu()
        state.shell = shell
        state.bindings = []

        func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command,
                  target: AnyObject? = shell, tag: Int = 0, object: Any? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = target
            i.tag = tag
            i.representedObject = object
            // Items that come with a shortcut can be rebound in Settings → Shortcuts.
            if let action, !key.isEmpty {
                state.bindings.append(MenuBinding(id: MenuLogic.bindingID(action: action, object: object as? String, tag: tag),
                                                  item: i, key: key, modifiers: mods))
            }
            return i
        }
        func editor(_ title: String, _ command: EditorCommand, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            item(title, #selector(Shell.editorCommand(_:)), key, mods, object: command.rawValue)
        }
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: title)
            items.forEach(sub.addItem)
            top.submenu = sub
            return top
        }
        @discardableResult
        func add(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let top = submenu(title, items)
            main.addItem(top)
            return top.submenu!
        }
        let sep = { NSMenuItem.separator() }

        let services = submenu("Services", [])
        NSApp.servicesMenu = services.submenu
        add("Super Notes", [
            item("About Super Notes", #selector(Shell.showAbout(_:))), sep(),
            item("Settings…", #selector(Shell.openSettings(_:)), ","), sep(),
            services, sep(),
            item("Hide Super Notes", #selector(NSApplication.hide(_:)), "h", target: NSApp),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option], target: NSApp),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:)), target: NSApp), sep(),
            item("Quit Super Notes", #selector(NSApplication.terminate(_:)), "q", target: NSApp),
        ])

        quickExportItem = item("Quick Export", #selector(Shell.quickExport(_:)), "s")
        let export = NSMenuItem(title: "Export Note", action: nil, keyEquivalent: "")
        let exportMenu = NSMenu(title: "Export Note")
        exportMenu.delegate = shell
        export.submenu = exportMenu
        let readOnly = item(MenuState.Toggle.readOnly.titles.off, #selector(Shell.toggleReadOnly(_:)), "r", [.command, .shift])
        let archive = item(MenuState.Toggle.archive.titles.off, #selector(MenuState.toggleArchive(_:)), "a", [.command, .shift],
                           target: state)
        let lock = item(MenuState.Toggle.lock.titles.off, #selector(Shell.toggleLock(_:)), "l", [.command, .shift])
        let file = add("File", [
            item("Create New Note", #selector(Shell.newNote(_:)), "n"),
            item("Move Note to Front", #selector(Shell.promoteToFront(_:)), "1", [.command, .shift]), sep(),
            item("Search All Notes", #selector(Shell.searchAllNotes(_:)), "f"),
            item("Command Palette…", #selector(Shell.showCommandPalette(_:)), "k"), sep(),
            editor("Find and Replace", .findAndReplace, "f", [.command, .shift]), sep(),
            item("Toggle Split Screen", #selector(Shell.toggleSplit(_:)), "t", [.command, .shift]), sep(),
            item("Swap Ephemeral vs. Slotted", #selector(Shell.swapPanes(_:)), "t"), sep(),
            readOnly, archive, lock, item("Relock Notes", #selector(Shell.relockNotes(_:))), sep(),
            item("Delete Note", #selector(Shell.moveToVoid(_:)), "d"), sep(),
            item("Recover Notes from The Void...", #selector(Shell.recoverFromVoid(_:))),
            item("Empty The Void", #selector(Shell.emptyVoid(_:))), sep(),
            item("Print...", #selector(Shell.printNote(_:)), "p", [.command, .shift]),
            export, sep(),
            item("Close Window", #selector(NSWindow.performClose(_:)), "w", target: nil),
        ])
        state.toggles = [(readOnly, .readOnly), (archive, .archive), (lock, .lock)]
        file.delegate = state

        add("Edit", [
            item("Undo", Selector(("undo:")), "z", target: nil),
            item("Redo", Selector(("redo:")), "z", [.command, .shift], target: nil), sep(),
            item("Cut", #selector(NSText.cut(_:)), "x", target: nil),
            item("Copy", #selector(NSText.copy(_:)), "c", target: nil),
            item("Paste", #selector(NSText.paste(_:)), "v", target: nil),
            item("Select All", #selector(NSText.selectAll(_:)), "a", target: nil), sep(),
            editor("Copy All", .copyAll, "c", [.command, .option]),
            editor("Select Line", .selectLine, "l"), sep(),
            editor("Find Next", .findNext, "g"),
            editor("Find Previous", .findPrevious, "g", [.command, .shift]), sep(),
            editor("Check Off Current Line", .toggleCheckbox, "k", [.command, .shift]),
            editor("Cycle List Type", .cycleListStyle, "m", [.command, .shift]),
            editor("Indent", .indent, "]", [.command, .option]),
            editor("Outdent", .outdent, "[", [.command, .option]), sep(),
            editor("Move Line Up", .moveLineUp, up, .option),
            editor("Move Line Down", .moveLineDown, down, .option),
            editor("Duplicate Line Up", .duplicateLineUp, up, [.option, .shift]),
            editor("Duplicate Line Down", .duplicateLineDown, down, [.option, .shift]), sep(),
            editor("Markdown: Strikethrough", .strikethrough, "x", [.command, .shift]), sep(),
            editor("Expand All Links", .expandAllLinks, "l", [.command, .option]),
            editor("Extension Autocomplete", .showExtensionAutocomplete, " ", .control),
        ])

        add("Appearance", [
            editor("Increase Text Size", .increaseTextSize, "="),
            editor("Decrease Text Size", .decreaseTextSize, "-"),
            editor("Reset Text Size", .resetTextSize, "0", [.command, .option]), sep(),
            item("Always Show Slots Bar", #selector(Shell.toggleSlotsBar(_:))),
            item("Split Horizontally", #selector(Shell.toggleSplitHorizontal(_:))), sep(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control], target: nil),
        ])

        let jump = item("Jump to Front", #selector(Shell.goToFirstNote(_:)), "1")
        let slotItems = [sep()]
            + (0..<SlotBoard.count).map { item("Go to Slot \($0 + 1)", #selector(Shell.openSlotItem(_:)), "\($0 + 1)", tag: $0) }
            + [item("Ephemeral Notes", #selector(Shell.goToDeck(_:)), "0")]
        let assign = submenu("Assign to Slot",
                             (0..<SlotBoard.count).map {
                                 item("Slot \($0 + 1)", #selector(Shell.assignSlotItem(_:)), "\($0 + 1)", [.command, .control], tag: $0)
                             } + [sep(), item("Remove from Slot", #selector(Shell.removeFromSlot(_:)))])
        add("Navigate", [jump,
                         item("Show Previous Note", #selector(Shell.previousNote(_:)), "["),
                         item("Show Next Note", #selector(Shell.nextNote(_:)), "]")]
            + slotItems + [sep(), assign])
        state.jumpToFront = jump
        state.slotItems = slotItems

        func supportItems() -> [NSMenuItem] {
            [item("Show Tutorial Notes", #selector(Shell.showTutorial(_:))),
             item("Keyboard Shortcuts", #selector(Shell.openShortcutsSettings(_:)))]
        }
        add("Support", supportItems())

        let pin = item(MenuState.Toggle.pin.titles.off, #selector(Shell.togglePin(_:)), "p")
        let window = add("Window", [
            pin,
            item("Hide/Show Super Notes", #selector(MenuState.toggleMainWindow(_:)), "o", target: state), sep(),
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", target: nil),
            item("Zoom", #selector(NSWindow.performZoom(_:)), target: nil), sep(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), target: NSApp),
        ])
        state.toggles.append((pin, .pin))
        window.delegate = state
        NSApp.windowsMenu = window

        NSApp.helpMenu = add("Help", supportItems())
        built = main
        state.observeBindings()
        return main
    }

    /// The Export Note menu. The main menu's copy (`forMainMenu`) holds the lasting Quick Export item; the others
    /// get a copy with its current shortcut.
    static func exportMenu(target: Shell, forMainMenu: Bool = false) -> NSMenu {
        let menu = NSMenu(title: "Export Note")
        for row in MenuLogic.exportRows(enabled: Defaults[.exportDestinations], quick: Defaults[.quickExportDestination]) {
            switch row {
            case .quickExport(let title):
                if forMainMenu, let quick = quickExportItem {
                    quick.menu?.removeItem(quick)
                    quick.title = title
                    menu.addItem(quick)
                } else {
                    let copy = menu.addItem(withTitle: title, action: #selector(Shell.quickExport(_:)),
                                            keyEquivalent: quickExportItem?.keyEquivalent ?? "s")
                    copy.keyEquivalentModifierMask = quickExportItem?.keyEquivalentModifierMask ?? .command
                    copy.target = target
                }
            case .destination(let title, let destination):
                let item = menu.addItem(withTitle: title, action: #selector(Shell.exportItem(_:)), keyEquivalent: "")
                item.target = target
                item.representedObject = destination.rawValue
            case .separator:
                menu.addItem(.separator())
            }
        }
        if menu.items.isEmpty {
            menu.addItem(withTitle: "No destinations enabled", action: nil, keyEquivalent: "").isEnabled = false
        }
        return menu
    }
}

/// Menu logic that doesn't need AppKit state (self-tested).
public enum MenuLogic {
    public static let upArrow = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
    public static let downArrow = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))

    /// Items that change title with state.
    public enum Toggle: CaseIterable, Sendable {
        case pin, readOnly, archive, lock

        public var titles: (off: String, on: String) {
            switch self {
            case .pin: ("Pin Super Notes to Top", "Unpin from Top")
            case .readOnly: ("Make Read-Only", "Allow Editing")
            case .archive: ("Archive Note", "Unarchive Note")
            case .lock: ("Lock Note", "Unlock Note")
            }
        }
    }

    /// One row of the Export Note menu.
    public enum ExportRow: Equatable, Sendable {
        case quickExport(String)
        case destination(String, ExportDestination)
        case separator
    }

    /// Export Note: Quick Export first, then files (text, Markdown, PDF), then the apps notes are sent to — enabled
    /// destinations only, groups split by separators.
    public static func exportRows(enabled: Set<ExportDestination>, quick: ExportDestination?) -> [ExportRow] {
        let files: [ExportDestination] = [.plainText, .markdown, .pdf]
        let apps: [ExportDestination] = [.bear, .obsidian, .appleNotes, .customURL]
        let groups: [[ExportRow]] = [
            quick.map { [.quickExport("Quick Export (\($0.displayName.replacingOccurrences(of: #" \(\..*\)$"#, with: "", options: .regularExpression)))")] } ?? [],
            files.filter(enabled.contains).map { .destination(exportName($0), $0) },
            apps.filter(enabled.contains).map { .destination($0 == .customURL ? exportName($0) : "Send to \(exportName($0))", $0) },
        ].filter { !$0.isEmpty }
        return Array(groups.joined(separator: [.separator]))
    }

    public static func exportName(_ destination: ExportDestination) -> String {
        switch destination {
        case .pdf: "PDF (.pdf)"
        case .customURL: "Custom Export"
        default: destination.displayName
        }
    }

    /// The modifiers a menu shortcut can use.
    public static let bindingModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    /// A menu item's id for its rebound shortcut: the action's name, then the command or slot it acts on
    /// ("newNote", "editorCommand.findAndReplace", "openSlotItem.3").
    public static func bindingID(action: Selector, object: String?, tag: Int) -> String {
        var id = NSStringFromSelector(action)
        if id.hasSuffix(":") { id.removeLast() }
        if let object { return id + "." + object }
        return tag != 0 || id.hasSuffix("SlotItem") ? id + ".\(tag)" : id
    }

    /// The shortcut a rebindable item gets: its override (nil = removed) or its built-in one.
    public static func shortcut(builtIn key: String, _ mods: NSEvent.ModifierFlags, override: Shortcut??) -> (String, NSEvent.ModifierFlags) {
        guard let override else { return (key, mods) }
        guard let shortcut = override else { return ("", []) }
        return (shortcut.keyEquivalent, shortcut.modifiers.intersection(bindingModifiers))
    }

    /// "⌃⌥⇧⌘K"-style text for a key equivalent.
    public static func display(_ key: String, _ mods: NSEvent.ModifierFlags) -> String {
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option) { s += "⌥" }
        if mods.contains(.shift) { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        switch key {
        case upArrow: return s + "↑"
        case downArrow: return s + "↓"
        case " ": return s + "Space"
        default: return s + key.uppercased()
        }
    }
}

/// A menu item whose shortcut can be rebound, with its built-in shortcut.
struct MenuBinding {
    let id: String
    let item: NSMenuItem
    let key: String
    let modifiers: NSEvent.ModifierFlags
}

/// Keeps state-dependent menu titles current ("Pin Super Notes to Top" / "Unpin from Top", …), shows the slot jumps
/// only while ⌘1…⌘9 belong to the slots, and applies rebound shortcuts as soon as they change.
@MainActor
final class MenuState: NSObject, NSMenuDelegate {
    typealias Toggle = MenuLogic.Toggle

    weak var shell: Shell?
    var toggles: [(NSMenuItem, Toggle)] = []
    weak var jumpToFront: NSMenuItem?
    var slotItems: [NSMenuItem] = []
    var bindings: [MenuBinding] = []
    private var cancellables: Set<AnyCancellable> = []

    private var currentNote: Note? { shell?.currentNoteID.flatMap { Services.store?.note($0) } }

    func isOn(_ toggle: Toggle) -> Bool {
        switch toggle {
        case .pin: Defaults[.pinOnTop]
        case .readOnly: currentNote?.isReadOnly == true
        case .archive: currentNote?.isArchived == true
        case .lock: currentNote?.isLocked == true
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for (item, toggle) in toggles where item.menu === menu {
            item.title = isOn(toggle) ? toggle.titles.on : toggle.titles.off
        }
    }

    func observeBindings() {
        cancellables = []
        for key in [Defaults.Keys.shellKitSlotNumberShortcuts, .menuShortcuts] {
            Defaults.changes.filter { $0 == key.name }.sink { [weak self] _ in self?.applyBindings() }.store(in: &cancellables)
        }
        applyBindings()
    }

    /// Every rebindable item gets its override or built-in shortcut. With slot shortcuts on, ⌘1…⌘9 open the
    /// slots and Jump to Front gives up ⌘1.
    func applyBindings() {
        let slotsOn = Defaults[.shellKitSlotNumberShortcuts]
        slotItems.forEach { $0.isHidden = !slotsOn }
        let overrides = Defaults[.menuShortcuts]
        for b in bindings {
            let builtIn = b.item === jumpToFront && slotsOn ? "" : b.key
            let (key, mods) = MenuLogic.shortcut(builtIn: builtIn, b.modifiers, override: overrides[b.id])
            b.item.keyEquivalent = key
            b.item.keyEquivalentModifierMask = mods
        }
    }

    @objc func toggleArchive(_ sender: Any?) {
        guard let shell, let note = currentNote else { return }
        if note.isArchived {
            Services.store?.setArchived(false, for: note.id)
            HUD.show("Note unarchived")
        } else {
            shell.archiveNote(sender)
        }
    }

    @objc func toggleMainWindow(_ sender: Any?) { shell?.toggleMain() }
}

extension MenuState: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        item.action == #selector(toggleArchive(_:)) ? currentNote != nil : true
    }
}
