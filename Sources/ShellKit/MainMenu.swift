import AppKit
import JotterCore

/// Builds the menu bar. Every item with a key equivalent is also recorded in `shortcuts`, which Settings →
/// Shortcuts lists — the menu is the single source of truth for keyboard shortcuts.
@MainActor
enum MainMenu {
    struct ShortcutEntry: Identifiable {
        let menu: String
        let title: String
        let keys: String
        var id: String { menu + "/" + title }
    }

    private(set) static var shortcuts: [ShortcutEntry] = []

    private static let up = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
    private static let down = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
    private static let backspace = String(Character(UnicodeScalar(NSBackspaceCharacter)!))

    static func build(target shell: Shell) -> NSMenu {
        shortcuts = []
        let main = NSMenu()
        var section = ""

        func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command,
                  target: AnyObject? = shell, tag: Int = 0, object: Any? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = target
            i.tag = tag
            i.representedObject = object
            if !key.isEmpty { shortcuts.append(ShortcutEntry(menu: section, title: title, keys: display(key, mods))) }
            return i
        }
        func editor(_ title: String, _ command: EditorCommand, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            item(title, #selector(Shell.editorCommand(_:)), key, mods, object: command.rawValue)
        }
        func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: title)
            items.forEach(sub.addItem)
            top.submenu = sub
            return top
        }
        func add(_ title: String, _ build: () -> [NSMenuItem]) -> NSMenu {
            section = title
            let m = menu(title, build())
            main.addItem(m)
            return m.submenu!
        }
        let sep = { NSMenuItem.separator() }

        _ = add("Jotter") {
            [item("About Jotter", #selector(Shell.showAbout(_:))), sep(),
             item("Settings…", #selector(Shell.openSettings(_:)), ","), sep(),
             item("Hide Jotter", #selector(NSApplication.hide(_:)), "h", target: NSApp),
             item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option], target: NSApp),
             item("Show All", #selector(NSApplication.unhideAllApplications(_:)), target: NSApp), sep(),
             item("Quit Jotter", #selector(NSApplication.terminate(_:)), "q", target: NSApp)]
        }

        _ = add("File") {
            let export = NSMenuItem(title: "Export", action: nil, keyEquivalent: "")
            let exportMenu = NSMenu(title: "Export")
            exportMenu.delegate = shell
            export.submenu = exportMenu
            return [item("New Note", #selector(Shell.newNote(_:)), "n"), sep(),
                    item("Move to The Void", #selector(Shell.moveToVoid(_:)), backspace),
                    item("Recover from The Void…", #selector(Shell.recoverFromVoid(_:)), backspace, [.command, .shift]), sep(),
                    export,
                    item("Quick Export", #selector(Shell.quickExport(_:)), "e", [.command, .shift]),
                    item("Print…", #selector(Shell.printNote(_:)), "p"), sep(),
                    item("Close Window", #selector(NSWindow.performClose(_:)), "w", target: nil)]
        }

        _ = add("Edit") {
            [item("Undo", Selector(("undo:")), "z", target: nil),
             item("Redo", Selector(("redo:")), "z", [.command, .shift], target: nil), sep(),
             item("Cut", #selector(NSText.cut(_:)), "x", target: nil),
             item("Copy", #selector(NSText.copy(_:)), "c", target: nil),
             item("Paste", #selector(NSText.paste(_:)), "v", target: nil),
             item("Select All", #selector(NSText.selectAll(_:)), "a", target: nil), sep(),
             editor("Copy All", .copyAll, "c", [.command, .option]),
             editor("Select Line", .selectLine, "l"), sep(),
             editor("Find…", .find, "f"),
             editor("Find & Replace…", .findAndReplace, "f", [.command, .option]),
             editor("Find Next", .findNext, "g"),
             editor("Find Previous", .findPrevious, "g", [.command, .shift]), sep(),
             editor("Expand All Links", .expandAllLinks, "l", [.command, .option]),
             editor("Extension Autocomplete", .showExtensionAutocomplete, " ", .control)]
        }

        _ = add("Note") {
            let assign = menu("Assign to Slot",
                              (0..<SlotBoard.count).map {
                                  item("Slot \($0 + 1)", #selector(Shell.assignSlotItem(_:)), "\($0 + 1)", [.command, .control], tag: $0)
                              } + [sep(), item("Remove from Slot", #selector(Shell.removeFromSlot(_:)))])
            return [editor("Toggle Checklist Item", .toggleCheckbox, "m", [.command, .shift]),
                    editor("Cycle List Style", .cycleListStyle, "m", [.command, .shift, .control]),
                    editor("Indent", .indent, "]", [.command, .option]),
                    editor("Outdent", .outdent, "[", [.command, .option]), sep(),
                    editor("Move Line Up", .moveLineUp, up, [.command, .option]),
                    editor("Move Line Down", .moveLineDown, down, [.command, .option]),
                    editor("Duplicate Line Up", .duplicateLineUp, up, [.command, .option, .shift]),
                    editor("Duplicate Line Down", .duplicateLineDown, down, [.command, .option, .shift]),
                    editor("Strikethrough", .strikethrough, "x", [.command, .shift]), sep(),
                    item("Promote to Front", #selector(Shell.promoteToFront(_:)), "t", [.command, .shift]),
                    assign, sep(),
                    item("Lock Note", #selector(Shell.toggleLock(_:)), "l", [.command, .control]),
                    item("Read-Only", #selector(Shell.toggleReadOnly(_:)), "r", [.command, .shift]),
                    item("Archive", #selector(Shell.archiveNote(_:)), "a", [.command, .shift])]
        }

        _ = add("View") {
            [editor("Increase Text Size", .increaseTextSize, "="),
             editor("Decrease Text Size", .decreaseTextSize, "-"),
             editor("Reset Text Size", .resetTextSize, "0", [.command, .option]), sep(),
             item("Pin on Top", #selector(Shell.togglePin(_:)), "p", [.command, .shift]),
             item("Always Show Slots Bar", #selector(Shell.toggleSlotsBar(_:))),
             item("Split View", #selector(Shell.toggleSplit(_:)), "s", [.command, .control]),
             item("Split Horizontally", #selector(Shell.toggleSplitHorizontal(_:))),
             item("Swap Ephemeral and Slotted", #selector(Shell.swapPanes(_:))), sep(),
             item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control], target: nil)]
        }

        _ = add("Go") {
            [item("Previous Note", #selector(Shell.previousNote(_:)), "["),
             item("Next Note", #selector(Shell.nextNote(_:)), "]"),
             item("First Note", #selector(Shell.goToFirstNote(_:)), "l", [.command, .shift]), sep(),
             item("Ephemeral Notes", #selector(Shell.goToDeck(_:)), "0")]
            + (0..<SlotBoard.count).map { item("Slot \($0 + 1)", #selector(Shell.openSlotItem(_:)), "\($0 + 1)", tag: $0) }
            + [sep(),
               item("Search All Notes…", #selector(Shell.searchAllNotes(_:)), "f", [.command, .shift]),
               item("Command Palette…", #selector(Shell.showCommandPalette(_:)), "k")]
        }

        let windowMenu = add("Window") {
            [item("Show Jotter", #selector(Shell.showMainWindow(_:))),
             item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", target: nil),
             item("Zoom", #selector(NSWindow.performZoom(_:)), target: nil), sep(),
             item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), target: NSApp)]
        }
        NSApp.windowsMenu = windowMenu

        let helpMenu = add("Help") {
            [item("Show Tutorial Notes", #selector(Shell.showTutorial(_:))),
             item("Keyboard Shortcuts", #selector(Shell.openShortcutsSettings(_:)))]
        }
        NSApp.helpMenu = helpMenu
        return main
    }

    /// Export destinations enabled in Settings → Export.
    static func exportMenu(target: Shell) -> NSMenu {
        let menu = NSMenu(title: "Export")
        let enabled = Defaults[.exportDestinations]
        for destination in ExportDestination.allCases where enabled.contains(destination) {
            let item = NSMenuItem(title: destination.displayName, action: #selector(Shell.exportItem(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = destination.rawValue
            menu.addItem(item)
        }
        if menu.items.isEmpty {
            let none = NSMenuItem(title: "No destinations enabled", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        return menu
    }

    static func display(_ key: String, _ mods: NSEvent.ModifierFlags) -> String {
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option) { s += "⌥" }
        if mods.contains(.shift) { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        switch key {
        case up: return s + "↑"
        case down: return s + "↓"
        case backspace: return s + "⌫"
        case " ": return s + "Space"
        default: return s + key.uppercased()
        }
    }
}
