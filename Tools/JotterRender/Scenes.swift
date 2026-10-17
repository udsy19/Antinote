import AppKit
import JotterCore
import EditorKit
import ShellKit

/// Every scene JotterRender knows. Sizes are window content sizes in points.
@MainActor
enum Scenes {
    static let window = NSSize(width: 337, height: 386)

    static var all: [Scene] {
        var scenes: [Scene] = []
        for (name, text) in Demo.notes {
            scenes.append(Scene(name: "editor-\(name)", size: window) { editor(text) })
            scenes.append(Scene(name: "editor-\(name)-dark", size: window, dark: true) { editor(text) })
        }
        scenes.append(Scene(name: "editor-pills", size: window) { pills() })
        scenes.append(Scene(name: "editor-linktip", size: window) { linkTip() })
        scenes.append(Scene(name: "editor-drop", size: window) { EditorPreview.dropOverlay(size: window) })
        scenes.append(Scene(name: "editor-autocomplete", size: window) { autocomplete() })
        scenes.append(Scene(name: "editor-autocomplete-dark", size: window, dark: true) { autocomplete() })
        scenes.append(Scene(name: "editor-slash", size: window) { slashList(query: "") })
        scenes.append(Scene(name: "editor-slash-dark", size: window, dark: true) { slashList(query: "") })
        scenes.append(Scene(name: "editor-slash-filtered", size: window) { slashList(query: "ti") })
        scenes.append(Scene(name: "editor-find", size: window) { EditorPreview.findShelf(Demo.notes[2].1, term: "the", replace: false) })
        scenes.append(Scene(name: "editor-find-replace", size: window) {
            EditorPreview.findShelf(Demo.notes[2].1, term: "the", replace: true)
        })
        scenes.append(Scene(name: "editor-find-replace-dark", size: window, dark: true) {
            EditorPreview.findShelf(Demo.notes[2].1, term: "the", replace: true)
        })
        scenes.append(Scene(name: "editor-bullet-list", size: window) { listStyle(.bullet) })
        // Last: each one leaves its theme selected (the editors restyle when the window lays them out).
        let themes = Theme.builtIn.filter { ["Meadow", "Armor", "Stealth", "Spice", "Bubblegum"].contains($0.name) }.map { theme in
            Scene(name: "theme-\(theme.id)", size: window, dark: theme.isDark) { themed(theme) }
        }
        return scenes + windows + settings + tools + themes
    }

    /// The "/" list under a line holding "/" plus `query`, filled with commands like the palette's.
    static func slashList(query: String) -> NSView {
        let view = editor("Groceries\nmilk and eggs\n/" + query)
        var commands = NoteMode.keywordModes.map { mode in
            PaletteCommand(title: "Insert Keyword: \(mode.mainKeyword)", detail: mode.summary, symbol: "text.insert",
                           keywords: mode.keywords.joined(separator: " "), keyword: mode.mainKeyword) {}
        }
        commands += [PaletteCommand(title: "New Note", symbol: "square.and.pencil", trailing: "⌘N") {},
                     PaletteCommand(title: "Search All Notes", symbol: "magnifyingglass", trailing: "⌘F") {}]
        if !query.isEmpty {
            commands = [PaletteCommand(title: "Insert Keyword: timer", detail: NoteMode.timer.summary, symbol: "text.insert",
                                       keyword: "timer") {},
                        PaletteCommand(title: "Start Pomodoro (25/5)", symbol: "timer") {},
                        PaletteCommand(title: "Settings: Timer", symbol: "gearshape") {}]
        }
        let list = EditorPreview.slashList(commands, query: query, width: window.width)
        list.setFrameOrigin(NSPoint(x: 33, y: window.height - 128 - list.frame.height))
        view.addSubview(list)
        return view
    }

    /// A list note whose plain lines took the bullet style.
    static func listStyle(_ style: ListStyle) -> NSView {
        Defaults[.defaultListStyle] = style
        defer { Defaults.reset(.defaultListStyle) }
        return editor("list: Weekend\nfarmers market\nfix the bike\n[x] call grandma\nbake bread")
    }

    /// The math demo note in `theme` (which stays selected for the rest of the run).
    static func themed(_ theme: Theme) -> NSView {
        Defaults[theme.isDark ? .darkTheme : .lightTheme] = theme.id
        return editor(Demo.notes[0].1)
    }

    /// A note editor showing `text` with the caret at the end.
    static func editor(_ text: String) -> NSView {
        let editor = JotterEditor()
        let shortened = Demo.shortenLinks(text)
        editor.load(Note(content: shortened.text, links: shortened.links))
        return editor.view
    }

    /// The plain demo note with the hover tip of its short link.
    static func linkTip() -> NSView {
        let view = editor(Demo.notes[2].1)
        view.frame = NSRect(origin: .zero, size: window)
        let tip = EditorPreview.linkTip("https://docs.gc.gov/ambi/tunnel-manual.pdf\n⌘+Click to open | Click to expand.",
                                        endingAt: NSPoint(x: 230, y: window.height - 300), in: view.bounds)
        view.addSubview(tip)
        return view
    }

    /// The `::` command list under a line ending in `::`.
    static func autocomplete() -> NSView {
        let view = editor("did you think i was a city\nbig enough for a weekend getaway\nBUT ALWAYS PASS THROUGH ::")
        func command(_ name: String, _ ext: String, _ action: String) -> ExtensionCommandInfo {
            ExtensionCommandInfo(name: name, aliases: [], extensionName: ext, helpText: "", signature: "", action: action)
        }
        let list = EditorPreview.completionList([
            command("uppercase_line", "line_format", "replaceLine"), command("trim_whitespace", "clean_line", "replaceLine"),
            command("title_case_line", "line_format", "replaceLine"), command("roll", "dice", "insert"),
            command("today", "date", "insert"),
        ], width: window.width)
        list.setFrameOrigin(NSPoint(x: 40, y: window.height - 120 - list.frame.height))
        view.addSubview(list)
        return view
    }

    /// The four pill kinds stacked over a plain note.
    static func pills() -> NSView {
        let view = editor("Pills\n\nInfo, success, warning and error.")
        let messages: [(String, PillKind)] = [("Empty note deleted", .info), ("Stopwatch started", .success),
                                              ("Slot not available", .warning), ("Failed to export PDF", .error)]
        for (i, (text, kind)) in messages.enumerated() {
            let pill = PillView()
            pill.configure(text, kind: kind, theme: Theme.current)
            pill.alphaValue = 1
            pill.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(pill)
            NSLayoutConstraint.activate([
                pill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                pill.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -PillView.bottomInset - CGFloat(i) * 30),
            ])
        }
        return view
    }
}

/// Demo notes modelled on the reference recordings.
@MainActor
enum Demo {
    static let notes: [(String, String)] = [
        ("math", """
        math: SpaceGarden beds

        Plants
        12 beds x 8 plants =

        Costs
        ($24.25 + $49.2) * 12 =

        Split across 3 people
        881.40 / 3 =
        """),
        ("list", """
        list
        [x] Refill starlight coffee capsules
        [x] Empty trash compactor (don't forget to SEAL)
        [ ] Sync biomons (https://biosync.io/devices/sync/374381)
        [ ] Order anti-grav slime for Kiran's science exp
        [ ] Sche call w/Serenity
        """),
        ("plain", """
        Quick Gotchas

        - When you open the post-quantum tunnel, make sure the Ambi is fully coolllled down

        - There are 38, not 28, different circuit patterns underneath panel AV648

        - The manual is here: https://docs.gc.gov/ambi/tunnel-manual.pdf
        """),
        ("variables", """
        math

        guests: 5
        cost per guest: $34
        guests * cost per guest =

        hourly rate: 23.75
        daily earnings: hourly rate * 8 =
        monthly salary: daily earnings * 20 =
        12 / 0 =
        """),
        ("markdown", """
        # Monday
        Ship the **beta** build
        ## Errands
        Pick up `film` at the lab
        // remember the receipt
        ### Later
        ~~Call the plumber~~
        ```
        let x = 42 // answer
        print("hi")
        ```
        """),
        ("sum", """
        sum

        $2 for apples, $25 for bus tickets, $6 for coffee and $4.25 for a bagel.
        """),
        ("code", """
        code: swift
        // greet someone
        func greet(_ name: String) -> String {
            let count = 3
            return "Hi, \\(name)"
        }
        """),
        ("mixed", """
        Groceries
        [] oat milk
        [x] bread
        - apples
        - pears
        1. first
        2. second
        """),
    ]

    /// Shortens raw URLs the way pasting does, so short links render.
    static func shortenLinks(_ text: String) -> (text: String, links: [ShortLink]) {
        guard let analyzer = Services.analyzer,
              let regex = try? NSRegularExpression(pattern: #"https?://[^\s)]+"#) else { return (text, []) }
        var result = text as NSString
        var links: [ShortLink] = []
        for m in regex.matches(in: text, range: NSRange(location: 0, length: result.length)).reversed() {
            let url = result.substring(with: m.range)
            let short = analyzer.shorten(url: url)
            links.append(ShortLink(url: url, short: short))
            result = result.replacingCharacters(in: m.range, with: short) as NSString
        }
        return (result as String, links)
    }
}

/// The main window with its chrome.
@MainActor
extension Scenes {
    static var windows: [Scene] {
        let size = WindowPreview.defaultSize
        return [Scene(name: "window-revealed", size: size) { windowFrame(revealed: true) },
                Scene(name: "window-rest", size: size) { windowFrame(revealed: false) },
                Scene(name: "window-revealed-dark", size: size, dark: true) { windowFrame(revealed: true) },
                // Last: opening a slot changes the shared window's state.
                Scene(name: "window-slot", size: size) { windowFrame(revealed: true, slot: 1) },
                Scene(name: "window-slot-own-theme", size: size) { slottedThemeFrame() },
                Scene(name: "window-locked", size: size) { lockedFrame() }]
            + chromeGlyphs
    }

    /// Seeds a few notes (the demo math note in front, two slotted notes) and snapshots the window frame, showing
    /// `slot` when given.
    private static func windowFrame(revealed: Bool, slot: Int? = nil) -> NSView {
        let store = Services.store!
        if store.deck.isEmpty {
            store.setSlot(1, for: store.create(content: "# Aphrodite\nSlot two.").id)
            store.setSlot(4, for: store.create(content: "# Zeus\nSlot five.").id)
            store.create(content: Demo.notes[2].1)
            store.create(content: Demo.notes[0].1)
        }
        return Render.drawn(WindowPreview.frameView(revealed: revealed, slot: slot))
    }

    /// Slot five with its own theme (Meadow) while ephemeral notes keep the default pair.
    private static func slottedThemeFrame() -> NSView {
        Defaults[.slottedLightTheme] = "meadow"
        defer { Defaults.reset(.slottedLightTheme) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))   // lets the editors restyle
        return windowFrame(revealed: true, slot: 4)
    }

    /// A locked note in slot seven, shown behind its lock screen.
    private static func lockedFrame() -> NSView {
        let store = Services.store!
        if store.deck.first(where: { $0.slot == 6 }) == nil {
            var note = store.create(content: "# Ouranos\nPrivate.")
            note.isLocked = true
            store.update(note)
            store.setSlot(6, for: note.id)
        }
        return windowFrame(revealed: false, slot: 6)
    }

    /// Frame views can't be re-parented, so render them (SwiftUI included) into an image view.
    static func snapshot(_ view: NSView) -> NSView {
        view.displayIfNeeded()
        let image = NSImage(size: view.bounds.size)
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            image.addRepresentation(rep)
        }
        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleNone
        imageView.imageAlignment = .alignTop
        return imageView
    }
}
