import AppKit
import JotterCore

/// `PanelServicing`: command palette (⌘K), Search All Notes (⇧⌘F) and The Void.
@MainActor
public final class ToolsPanels: PanelServicing {
    private let palette = CommandPalette()
    private let void = VoidWindowController()
    private lazy var search = QuickPanel(placeholder: "Search All Notes", emptyText: "Try a different search term",
                                         provider: Self.searchRows)

    public init() {}

    public func showCommandPalette() {
        if palette.isVisible { palette.close() } else { search.close(); palette.show() }
    }

    public func showVoid() { void.show() }

    public func showSearch() { showSearch(query: "") }

    public func showSearch(query: String) {
        palette.close()
        search.show(query: query)
    }

    private static func searchRows(_ query: String) -> [QuickPanel.Row] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, Services.store != nil else { return [] }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return Services.store.search(q, includeArchived: true).prefix(100).map { note in
            let snippet = SearchSnippet.make(note.content, query: q)
            let title = note.title.isEmpty ? "Empty note" : note.title
            let titleHits = SearchSnippet.make(title, query: q, radius: 200)
            return QuickPanel.Row(
                title: .highlighting(titleHits.text, ranges: titleHits.highlights, size: 13),
                detail: .highlighting(snippet.text, ranges: snippet.highlights),
                symbol: note.isArchived ? "archivebox" : note.slot != nil ? "pin.square" : "doc.text",
                trailing: formatter.localizedString(for: note.modified, relativeTo: Date()),
                action: { Services.windows.show(noteID: note.id) })
        }
    }
}
