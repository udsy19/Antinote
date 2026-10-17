import AppKit
import Combine
import JotterCore

/// `PanelServicing`: command palette (⌘K), Search All Notes (shown inside the main window) and The Void.
@MainActor
public final class ToolsPanels: PanelServicing {
    private let palette = CommandPalette()
    private let void = VoidWindowController()
    private var search: SearchPane?
    private var storeSubscription: AnyCancellable?

    public init() {}

    public func showCommandPalette() {
        if palette.isVisible { palette.close() } else { palette.show() }
    }

    public func showVoid() { void.show() }

    public func emptyVoid() { VoidModel().emptyVoid() }

    public func showSearch() { showSearch(query: "") }

    public func showSearch(query: String) {
        palette.close()
        guard Services.windows != nil, Services.store != nil else { return }
        let pane = search ?? makeSearch()
        search = pane
        if pane.superview == nil { Services.windows.present(inWindow: pane) }
        pane.query = query
        pane.focusField()
    }

    private func makeSearch() -> SearchPane {
        let pane = SearchPane(source: .init(deck: { Services.store?.deck ?? [] },
                                            archived: { Services.store?.archived ?? [] },
                                            now: Date.init))
        pane.onClose = { [weak self] in self?.closeSearch() }
        storeSubscription = Services.store.changes.receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated {
                guard let pane = self?.search, pane.superview != nil else { return }
                pane.reload()
            }
        }
        return pane
    }

    private func closeSearch() {
        guard search?.superview != nil else { return }
        Services.windows?.present(inWindow: nil)
    }
}

/// Views built for offscreen renders (JotterRender): the same views the app shows, fed fixed data.
@MainActor
public enum ToolsPreviews {
    /// The Search pane listing `notes` (front first) as a list or as cards, dated against `now`.
    /// With `selecting`, Select mode is on with the first two results picked.
    public static func search(notes: [Note], query: String = "", cards: Bool = false, selecting: Bool = false,
                              now: Date = Date()) -> NSView {
        let pane = SearchPane(source: .init(deck: { notes }, archived: { [] }, now: { now }))
        pane.setLayout(cards ? .cards : .list)
        pane.query = query
        if selecting { pane.select(notes.prefix(2).map(\.id)) }
        return pane
    }

    /// The Void listing `notes` (deleted notes, newest first).
    public static func void(notes: [Note], now: Date = Date()) -> NSView { VoidView.preview(notes: notes, now: now) }

    /// The pomodoro break screen with a fixed fact, time left and streak.
    public static func breakScreen(fact: String, remaining: TimeInterval, streak: NoPeekStreak) -> NSView {
        TimerOverlay.preview(.breakTime(.init(noteID: UUID(), fact: fact, remaining: { remaining }, isPaused: { false },
                                              togglePause: {}, end: {}, peek: {}, streak: { streak })))
    }

    /// A timer alert ("Your countdown timer is over.", "Break's over").
    public static func timerAlert(title: String, subtitle: String, message: String) -> NSView {
        TimerOverlay.preview(.alert(title: title, subtitle: subtitle, message: message))
    }
}
