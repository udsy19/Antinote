// swift-tools-version:5.10
import PackageDescription

// Jotter — a scratchpad for macOS. Feature modules depend only on JotterCore; the app target wires them
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
    name: "Jotter",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Jotter", targets: ["Jotter"])],
    targets: [
        .target(name: "JotterCore", path: "Sources/JotterCore"),
        .executableTarget(name: "Jotter", dependencies: ["JotterCore"] + modules.map { .target(name: $0) },
                          path: "Sources/Jotter"),
        .executableTarget(name: "JotterSelfTest", dependencies: ["JotterCore"] + modules.map { .target(name: $0) },
                          path: "Sources/JotterSelfTest"),
        // Offscreen PNG renders of the UI for visual checks: `.build/debug/JotterRender <out-dir> [scene…]`.
        .executableTarget(name: "JotterRender", dependencies: ["JotterCore"] + modules.map { .target(name: $0) },
                          path: "Tools/JotterRender"),
    ] + modules.map { name -> Target in
        name == "ExtensionsKit"
            ? .target(name: name, dependencies: ["JotterCore"], path: "Sources/\(name)", resources: [.copy("Bundled")])
            : .target(name: name, dependencies: ["JotterCore"], path: "Sources/\(name)")
    }
)
