// swift-tools-version:5.10
import PackageDescription

// Super Notes — a scratchpad for macOS. Feature modules depend only on SuperNotesCore; the app target wires them
// together through the `Services` registry.
let modules = [
    "StorageKit",     // SQLite note store, The Void, backups, encrypted iCloud Drive sync
    "NoteEngine",     // first-line keywords, math & units & currencies, sum/avg/count, lists, links, paste cleaning
    "ExtensionsKit",  // JavaScript extensions (JavaScriptCore), `::` commands, API bridge, bundled extensions
    "EditorKit",      // the plain-text editor: checklists, inline results, links, code, Vim mode, find & replace
    "ShellKit",       // main window & presence, swipe deck, slots, global hotkey, menus, settings, themes, locking,
                      // onboarding & tutorial notes
    "ToolsKit",       // timers & pomodoro, export, URL scheme, command palette, The Void, search
]

let package = Package(
    name: "SuperNotes",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SuperNotes", targets: ["SuperNotes"])],
    targets: [
        .target(name: "SuperNotesCore", path: "Sources/SuperNotesCore"),
        .executableTarget(name: "SuperNotes", dependencies: ["SuperNotesCore"] + modules.map { .target(name: $0) },
                          path: "Sources/SuperNotes"),
        .executableTarget(name: "SuperNotesSelfTest", dependencies: ["SuperNotesCore"] + modules.map { .target(name: $0) },
                          path: "Sources/SuperNotesSelfTest"),
        // Offscreen PNG renders of the UI for visual checks: `.build/debug/SuperNotesRender <out-dir> [scene…]`.
        .executableTarget(name: "SuperNotesRender", dependencies: ["SuperNotesCore"] + modules.map { .target(name: $0) },
                          path: "Tools/SuperNotesRender"),
    ] + modules.map { name -> Target in
        name == "ExtensionsKit"
            ? .target(name: name, dependencies: ["SuperNotesCore"], path: "Sources/\(name)", resources: [.copy("Bundled")])
            : .target(name: name, dependencies: ["SuperNotesCore"], path: "Sources/\(name)")
    }
)
