import AppKit
import JotterCore
import ToolsKit

/// Search, timer alert and other ToolsKit scenes.
@MainActor
extension Scenes {
    static var tools: [Scene] {
        let alert = NSSize(width: 900, height: 580)
        return [
            Scene(name: "search-list", size: window) { ToolsPreviews.search(notes: SearchDemo.notes, now: SearchDemo.now) },
            Scene(name: "search-list-dark", size: window, dark: true) {
                ToolsPreviews.search(notes: SearchDemo.notes, now: SearchDemo.now)
            },
            Scene(name: "search-list-wide", size: NSSize(width: 660, height: 440)) {
                ToolsPreviews.search(notes: SearchDemo.notes, now: SearchDemo.now)
            },
            Scene(name: "search-query", size: window) {
                ToolsPreviews.search(notes: SearchDemo.notes, query: "milk", now: SearchDemo.now)
            },
            Scene(name: "search-empty", size: window) {
                ToolsPreviews.search(notes: SearchDemo.notes, query: "zebra crossing", now: SearchDemo.now)
            },
            Scene(name: "search-cards", size: window) {
                ToolsPreviews.search(notes: SearchDemo.notes, cards: true, now: SearchDemo.now)
            },
            Scene(name: "search-cards-wide", size: NSSize(width: 660, height: 440)) {
                ToolsPreviews.search(notes: SearchDemo.notes, cards: true, now: SearchDemo.now)
            },
            Scene(name: "search-cards-dark", size: window, dark: true) {
                ToolsPreviews.search(notes: SearchDemo.notes, cards: true, now: SearchDemo.now)
            },
            Scene(name: "timer-break", size: alert) {
                ToolsPreviews.breakScreen(fact: "Ostriches can outrun most horses.", remaining: 291,
                                          streak: NoPeekStreak(current: 0, best: 0))
            },
            Scene(name: "timer-countdown", size: alert) {
                ToolsPreviews.timerAlert(title: "Time’s up", subtitle: "Countdown", message: "Your countdown timer is over.")
            },
        ]
    }
}

/// Notes for the Search scenes, dated relative to a fixed "now".
@MainActor
enum SearchDemo {
    static let now = Date(timeIntervalSince1970: 1_760_000_000)

    static let notes: [Note] = [
        note("+opensourceobserver.dev/...single-purpose-software+", hoursAgo: 6),
        note("list\n[ ] Reply to Discord thread about widgets.\n[ ] Return paint gun rental.\n"
             + "[ ] Does Spotlight index hidden files?\n[ ] sqlite3 notes.db", hoursAgo: 3),
        note("SQLite supports FTS5.\nRain-X doesn't last as long on side windows.\n\"The interface should disappear.\"\n"
             + "Ketchup freezes surprisingly well.\nUSB-C PD 100 W = 20 V × 5 A.", hoursAgo: 6),
        note("math\nmilk: $4.25\nbread: $3\nmilk * 2 + bread =", hoursAgo: 30),
        note("Penguins have knees.\nBees can recognize human faces.\nThe smell after rain is called petrichor.",
             hoursAgo: 60 * 24),
        note("code: swift\nstatic func spacing(size: Int) -> CGFloat {\n    size * 2\n}", hoursAgo: 80 * 24),
    ]

    private static func note(_ text: String, hoursAgo: Double) -> Note {
        let date = now.addingTimeInterval(-hoursAgo * 3600)
        return Note(content: text, created: date, modified: date)
    }
}
