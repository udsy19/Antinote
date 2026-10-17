import AppKit
import JotterCore

/// One palette entry. `keywords` are extra searchable words (matched with a lower score than the title).
struct PaletteItem {
    var title: String
    var detail: String?
    var symbol: String
    var trailing: String?
    var keywords: String = ""
    /// Set for "go to note" items, so full-text hits don't repeat them.
    var noteID: UUID?
    var action: () -> Void
}

/// ⌘K: every action plus note matches, fuzzy-filtered.
@MainActor
final class CommandPalette {
    private lazy var panel = QuickPanel(placeholder: "Type a command or search notes…",
                                        emptyText: "Try a different search term") { [weak self] query in
        self?.rows(for: query) ?? []
    }

    var isVisible: Bool { panel.isVisible }
    func show() { panel.show() }
    func close() { panel.close() }

    private func rows(for query: String) -> [QuickPanel.Row] {
        let items = actions() + noteItems()
        let ranked: [(PaletteItem, FuzzyMatcher.Match)] = items.enumerated().compactMap { offset, item in
            let byTitle = FuzzyMatcher.match(query, in: item.title)
            let byKeyword = item.keywords.isEmpty ? nil : FuzzyMatcher.match(query, in: item.keywords)
                .map { FuzzyMatcher.Match(score: $0.score - 20, indices: []) }
            guard let best = [byTitle, byKeyword].compactMap({ $0 }).max(by: { $0.score < $1.score }) else { return nil }
            return (item, best)
        }
        // Stable: sort by score, keep declaration order for ties.
        let ordered = ranked.enumerated().sorted {
            $0.element.1.score != $1.element.1.score ? $0.element.1.score > $1.element.1.score : $0.offset < $1.offset
        }.map(\.element)
        var result = ordered.prefix(60).map { item, match in
            QuickPanel.Row(title: .highlighting(item.title, offsets: match.indices),
                           detail: item.detail.map { NSAttributedString(string: $0) },
                           symbol: item.symbol, trailing: item.trailing, action: item.action)
        }
        // Full-text hits that the titles didn't already cover.
        if query.count >= 2, Services.store != nil {
            let shown = Set(ordered.compactMap { $0.0.noteID })
            for note in Services.store.search(query, includeArchived: false).prefix(10)
            where !shown.contains(note.id) {
                let snippet = SearchSnippet.make(note.content, query: query)
                result.append(QuickPanel.Row(title: NSAttributedString(string: note.title.isEmpty ? "Empty note" : note.title),
                                             detail: .highlighting(snippet.text, ranges: snippet.highlights),
                                             symbol: "text.magnifyingglass", trailing: nil,
                                             action: { Services.windows.show(noteID: note.id) }))
            }
        }
        return result
    }

    // MARK: Items

    private var currentNote: Note? {
        guard Services.windows != nil, Services.store != nil, let id = Services.windows.currentNoteID else { return nil }
        return Services.store.note(id)
    }

    private func actions() -> [PaletteItem] {
        var items: [PaletteItem] = [
            PaletteItem(title: "New Note", symbol: "square.and.pencil", trailing: "⌘N", keywords: "create add") {
                Services.windows.show(noteID: Services.store.create(content: "").id)
            },
            PaletteItem(title: "Search All Notes", symbol: "magnifyingglass", trailing: "⇧⌘F", keywords: "find") {
                Services.panels.showSearch()
            },
            PaletteItem(title: "The Void", detail: "Recover or erase deleted notes", symbol: "tornado",
                        keywords: "trash deleted recover restore") { Services.panels.showVoid() },
            PaletteItem(title: Defaults[.pinOnTop] ? "Unpin Window" : "Pin Window on Top", symbol: "pin",
                        keywords: "float always on top") {
                Defaults[.pinOnTop].toggle()
                HUD.show(Defaults[.pinOnTop] ? "Pinned on top" : "Unpinned", symbol: "pin")
            },
            PaletteItem(title: "Export All Notes…", symbol: "square.and.arrow.up.on.square", keywords: "backup markdown") {
                (Services.export as? ExportManager)?.exportAllInteractively()
            },
        ]
        if let note = currentNote {
            items += noteActions(note)
        }
        items += timerItems()
        items += settingsItems()
        items += keywordItems()
        items += extensionItems()
        return items
    }

    private func noteActions(_ note: Note) -> [PaletteItem] {
        var items = Defaults[.exportDestinations].sorted { $0.rawValue < $1.rawValue }.map { destination in
            PaletteItem(title: "Export to \(destination.displayName)", symbol: "square.and.arrow.up",
                        keywords: "share send") { Services.export.export(note, to: destination) }
        }
        items.append(PaletteItem(title: "Print Note", symbol: "printer", trailing: "⌘P", keywords: "pdf paper") {
            (Services.export as? ExportManager)?.print(note)
        })
        if note.slot == nil && note.position != 0 {
            items.append(PaletteItem(title: "Promote to Front", symbol: "arrow.up.to.line", keywords: "move top first") {
                Services.store.promoteToFront(note.id)
                HUD.show("Promoted note to front")
            })
        }
        items.append(PaletteItem(title: "Send to The Void", symbol: "trash", keywords: "delete remove") {
            Services.store.moveToVoid(note.id)
            HUD.show("Note sent to The Void", symbol: "tornado")
        })
        return items
    }

    private func noteItems() -> [PaletteItem] {
        guard Services.store != nil else { return [] }
        let slots = Services.store.deck.filter { $0.slot != nil }.sorted { ($0.slot ?? 0) < ($1.slot ?? 0) }
        let slotItems = slots.map { note in
            PaletteItem(title: "Slot \((note.slot ?? 0) + 1): \(note.title.isEmpty ? "Empty note" : note.title)",
                        symbol: "pin.square", trailing: "Slot \((note.slot ?? 0) + 1)",
                        noteID: note.id) { Services.windows.show(noteID: note.id) }
        }
        let deckItems = Services.store.deck.filter { $0.slot == nil && !$0.title.isEmpty }.map { note in
            PaletteItem(title: note.title, detail: "Go to note", symbol: "doc.text",
                        noteID: note.id) { Services.windows.show(noteID: note.id) }
        }
        return slotItems + deckItems
    }

    private func timerItems() -> [PaletteItem] {
        func startTimer(_ line: String, _ arguments: String) {
            let note = Services.store.create(content: line + "\n")
            Services.windows.show(noteID: note.id)
            Services.timers.start(noteID: note.id, arguments: arguments)
        }
        let work = Defaults[.pomodoroWorkMinutes], rest = Defaults[.pomodoroBreakMinutes]
        var items = [
            PaletteItem(title: "Start Pomodoro (\(work)/\(rest))", symbol: "timer", keywords: "focus work timer") {
                startTimer("timer pomo", "pomo")
            },
            PaletteItem(title: "Start 5-Minute Countdown", symbol: "hourglass", keywords: "timer") {
                startTimer("timer 5m", "5m")
            },
            PaletteItem(title: "Start Stopwatch", symbol: "stopwatch", keywords: "timer") { startTimer("timer", "") },
            PaletteItem(title: "Breathe", detail: "Slow breathing with a guide circle", symbol: "wind", keywords: "calm relax timer") {
                TimerOverlay.shared.showBreathing()
            },
        ]
        guard let manager = Services.timers as? TimerManager, Services.store != nil else { return items }
        for id in manager.runningNoteIDs {
            guard let run = manager.run(noteID: id) else { continue }
            let label = run.statusText(at: Date())
            items.append(PaletteItem(title: run.isPaused ? "Resume Timer" : "Pause Timer", detail: label,
                                     symbol: run.isPaused ? "play" : "pause", keywords: "timer") {
                manager.togglePause(noteID: id)
            })
            items.append(PaletteItem(title: "Show Timer Full Screen", detail: label, symbol: "arrow.up.left.and.arrow.down.right",
                                     keywords: "timer big") { manager.showFullScreen(noteID: id) })
            items.append(PaletteItem(title: "Stop Timer", detail: label, symbol: "stop", keywords: "timer") {
                manager.stop(noteID: id)
            })
        }
        return items
    }

    /// Settings tabs (ids are the lower-cased first word of the tab name).
    static let settingsTabs = ["General", "Appearance", "Writing", "Lists", "Math", "Copy & Paste", "Keywords",
                               "Timers", "Notes & Storage", "Privacy", "Extensions", "Advanced"]

    private func settingsItems() -> [PaletteItem] {
        Self.settingsTabs.map { tab in
            PaletteItem(title: "Settings: \(tab)", symbol: "gearshape", trailing: tab == "General" ? "⌘," : nil,
                        keywords: "preferences") {
                Services.windows.showSettings(tab: tab.split(separator: " ").first.map { $0.lowercased() })
            }
        }
    }

    private func keywordItems() -> [PaletteItem] {
        guard currentNote != nil else { return [] }
        return NoteMode.allCases.filter { $0 != .plain }.compactMap { mode in
            guard let keyword = mode.keywords.first else { return nil }
            return PaletteItem(title: "Insert Keyword: \(keyword)", detail: mode.displayName, symbol: "text.insert",
                               keywords: mode.keywords.joined(separator: " ")) { [weak self] in
                self?.setKeyword(keyword)
            }
        }
    }

    private func extensionItems() -> [PaletteItem] {
        guard Services.extensions != nil, currentNote != nil, Defaults[.extensionsEnabled] else { return [] }
        return Services.extensions.commands.map { command in
            PaletteItem(title: "::" + command.name, detail: command.helpText, symbol: "puzzlepiece.extension",
                        trailing: command.extensionName,
                        keywords: ([command.helpText] + command.aliases).joined(separator: " ")) { [weak self] in
                self?.appendLine("::\(command.name)()")
            }
        }
    }

    // MARK: Editing the current note

    /// Makes `keyword` the note's first line (replacing an existing keyword line).
    private func setKeyword(_ keyword: String) {
        guard var note = currentNote else { return }
        var lines = note.content.components(separatedBy: "\n")
        if let first = lines.first, NoteMode.detect(firstLine: first).mode != .plain {
            lines[0] = keyword
        } else {
            lines.insert(keyword, at: 0)
        }
        note.content = lines.joined(separator: "\n")
        Services.store.update(note)
        Services.windows.show(noteID: note.id)
    }

    private func appendLine(_ line: String) {
        guard var note = currentNote else { return }
        note.content = URLCommand.appending(line, to: note.content)
        Services.store.update(note)
        Services.windows.show(noteID: note.id)
    }
}
