import Foundation

// Pure, UI-free rules behind the shell (covered by JotterSelfTest).

// MARK: - Swipe gestures

public enum SwipeDirection: Equatable, Sendable {
    /// Fingers moved right: show the previous (older) note.
    case previous
    /// Fingers moved left: show the next (newer) note.
    case next
}

/// Turns phased trackpad scroll events into at most one deck step per gesture.
///
/// Like Antinote, a swipe is decided at the very start of the gesture: as soon as the first movement is mostly
/// horizontal and exceeds the threshold, the note switches; the rest of that gesture (and its momentum) is swallowed.
/// Gestures that start vertical, or don't clear the threshold within the first few events, scroll normally.
public struct SwipeAccumulator: Sendable {
    public enum Phase: Sendable { case began, changed, ended, momentum }
    public enum Outcome: Equatable, Sendable {
        /// Not ours (vertical scroll, mouse wheel…): let the event through.
        case pass
        /// Part of a horizontal gesture: swallow the event.
        case consume
        case navigate(SwipeDirection)
    }

    /// 0…1 — higher values require more deliberate swipes.
    public var sensitivity: Double
    private var dx = 0.0, dy = 0.0
    private var moves = 0
    private var state = State.deciding
    private enum State { case deciding, swiping, scrolling }

    public init(sensitivity: Double) { self.sensitivity = sensitivity }

    /// Moving events inspected before a gesture that hasn't cleared the threshold is left to scroll.
    public static let decisionWindow = 3
    /// Horizontal travel (points) needed within the decision window: any horizontal start at the lightest setting
    /// (Antinote's default), 30 pt at the firmest.
    public var threshold: Double { 30 * min(max(sensitivity, 0), 1) }

    /// `fingerDX` is positive when the fingers move right (independent of natural scrolling).
    public mutating func feed(phase: Phase, fingerDX: Double, fingerDY: Double) -> Outcome {
        switch phase {
        case .began:
            dx = 0; dy = 0; moves = 0; state = .deciding
            return decide(fingerDX, fingerDY)
        case .changed:
            return decide(fingerDX, fingerDY)
        case .ended, .momentum:
            if state == .deciding { state = .scrolling }
            return state == .swiping ? .consume : .pass
        }
    }

    private mutating func decide(_ fdx: Double, _ fdy: Double) -> Outcome {
        switch state {
        case .swiping: return .consume
        case .scrolling: return .pass
        case .deciding:
            guard fdx != 0 || fdy != 0 else { return .pass }
            dx += fdx; dy += fdy; moves += 1
            if abs(dy) >= abs(dx) { state = .scrolling; return .pass }
            if abs(dx) > threshold {
                state = .swiping
                return .navigate(dx > 0 ? .previous : .next)
            }
            if moves >= Self.decisionWindow { state = .scrolling; return .pass }
            return .consume
        }
    }
}

// MARK: - Deck navigation

public enum DeckStep: Equatable, Sendable {
    case show(index: Int)
    case createNew
    /// Nothing to do; `reason` is shown as a HUD when non-nil.
    case stay(reason: String?)
}

/// Index math over the ephemeral deck (index 0 = front, the newest note).
public enum DeckNavigator {
    public static func step(from index: Int, count: Int, direction: SwipeDirection, currentIsEmpty: Bool) -> DeckStep {
        guard count > 0 else { return .createNew }
        let i = min(max(index, 0), count - 1)
        switch direction {
        case .previous:
            return i + 1 < count ? .show(index: i + 1) : .stay(reason: "This is the oldest note")
        case .next:
            if i > 0 { return .show(index: i - 1) }
            return currentIsEmpty ? .stay(reason: "Already at latest") : .createNew
        }
    }

    public static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Slots

/// The nine numbered slots. Pure assignment rules; the caller applies the returned changes to the store.
public struct SlotBoard: Equatable, Sendable {
    public static let count = 9
    /// slot index → note
    public private(set) var occupants: [Int: UUID]

    public init(notes: [(id: UUID, slot: Int?)]) {
        var o: [Int: UUID] = [:]
        for n in notes { if let s = n.slot, Self.isValid(s), o[s] == nil { o[s] = n.id } }
        occupants = o
    }

    public static func isValid(_ slot: Int) -> Bool { (0..<count).contains(slot) }
    public func slot(of id: UUID) -> Int? { occupants.first { $0.value == id }?.key }
    public var firstFree: Int? { (0..<Self.count).first { occupants[$0] == nil } }
    public var isEmpty: Bool { occupants.isEmpty }

    /// Assigns `id` to `slot`, returning the slot changes to store (note → new slot or nil).
    /// Re-assigning a note to its own slot takes it out of the slot; an occupant is pushed back to the deck.
    public mutating func assign(_ id: UUID, to slot: Int) -> [(id: UUID, slot: Int?)] {
        guard Self.isValid(slot) else { return [] }
        if occupants[slot] == id {
            occupants[slot] = nil
            return [(id, nil)]
        }
        var changes: [(id: UUID, slot: Int?)] = []
        if let old = self.slot(of: id) { occupants[old] = nil }
        if let other = occupants[slot] { changes.append((other, nil)) }
        occupants[slot] = id
        changes.append((id, slot))
        return changes
    }

    public mutating func remove(_ id: UUID) -> [(id: UUID, slot: Int?)] {
        guard let s = slot(of: id) else { return [] }
        occupants[s] = nil
        return [(id, nil)]
    }
}

// MARK: - Window chrome

/// Text shown by the window chrome.
public enum ChromeText {
    /// A shortcut as chrome tooltips show it: modifiers in the order ⌘⇧⌥⌃, then the key in upper case ("⌘⇧F",
    /// "⌘[", "⌘⌫"). `key` is a menu item's key equivalent.
    public static func shortcut(key: String, command: Bool, shift: Bool, option: Bool, control: Bool) -> String {
        var s = ""
        if command { s += "⌘" }
        if shift { s += "⇧" }
        if option { s += "⌥" }
        if control { s += "⌃" }
        switch key {
        case "\u{8}", "\u{7F}": return s + "⌫"
        case " ": return s + "Space"
        case "\u{F700}": return s + "↑"
        case "\u{F701}": return s + "↓"
        default: return s + key.uppercased()
        }
    }

    /// A tooltip: "Label - ⌘N", or just the label when there is no shortcut.
    public static func tooltip(_ label: String, shortcut: String?) -> String {
        shortcut.map { "\(label) - \($0)" } ?? label
    }

    /// A destination name without its file-type note ("Markdown (.md)" → "Markdown").
    public static func shortName(_ name: String) -> String {
        name.range(of: " (").map { String(name[..<$0.lowerBound]) } ?? name
    }
}

/// The slot bar's geometry: nine planets in 22 pt frames 3 pt apart (the open slot's frame is 28 pt), 16 pt of
/// padding each side.
public enum SlotBarLayout {
    public static let padding: Double = 16
    public static let spacing: Double = 3
    public static let planetSize: Double = 22
    public static let openPlanetSize: Double = 28

    /// Frame widths of the nine planets, left to right.
    public static func frames(open: Int?) -> [Double] {
        (0..<SlotBoard.count).map { $0 == open ? openPlanetSize : planetSize }
    }

    /// Left edge of `slot`'s frame.
    public static func x(of slot: Int, open: Int?) -> Double {
        let f = frames(open: open)
        return padding + f[..<slot].reduce(0, +) + spacing * Double(slot)
    }

    /// The bar's width.
    public static func width(open: Int?) -> Double {
        let f = frames(open: open)
        return padding * 2 + f.reduce(0, +) + spacing * Double(f.count - 1)
    }
}

// MARK: - Locked notes

/// Which locked notes are open in this session. Unlocks expire `minutes` after a locked note was last in focus.
public struct RelockSession: Sendable {
    public private(set) var unlocked: Set<UUID> = []
    private var lastFocus: Date?
    /// True while an unlocked locked note is the visible, focused note (the clock does not run).
    private var focused = false

    public init() {}

    public mutating func unlock(_ id: UUID, at now: Date) {
        unlocked.insert(id); lastFocus = now
    }

    /// Reports whether a locked note is currently in focus; leaving restarts the clock from `now`.
    public mutating func setFocused(_ isFocused: Bool, at now: Date) {
        if focused || isFocused { lastFocus = now }
        focused = isFocused
    }

    public mutating func lock(_ id: UUID) { unlocked.remove(id) }

    public mutating func relockAll() { unlocked.removeAll(); lastFocus = nil; focused = false }

    /// Relocks everything when the timeout has passed; returns true if something was relocked.
    @discardableResult
    public mutating func expireIfNeeded(now: Date, minutes: Int) -> Bool {
        guard !unlocked.isEmpty, !focused, let lastFocus else { return false }
        guard now.timeIntervalSince(lastFocus) >= Double(max(minutes, 0)) * 60 else { return false }
        unlocked.removeAll()
        return true
    }

    public mutating func isUnlocked(_ id: UUID, now: Date, minutes: Int) -> Bool {
        expireIfNeeded(now: now, minutes: minutes)
        return unlocked.contains(id)
    }
}

// MARK: - Inactivity

public enum InactivityPolicy {
    /// Whether showing the window should start on a fresh note.
    public static func shouldStartFresh(lastHidden: Date?, now: Date, minutes: Int) -> Bool {
        guard minutes > 0, let lastHidden else { return false }
        return now.timeIntervalSince(lastHidden) >= Double(minutes) * 60
    }
}

// MARK: - Settings tabs

/// The Settings window's toolbar tabs, in order.
public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general, appearance, editor, notes, keywords, shortcuts, timer, export, extensions, privacy, updates

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .editor: "Editor"
        case .notes: "Notes"
        case .keywords: "Keywords"
        case .shortcuts: "Shortcuts"
        case .timer: "Timer"
        case .export: "Export"
        case .extensions: "Extensions"
        case .privacy: "Privacy"
        case .updates: "Updates"
        }
    }

    public var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "swatchpalette"
        case .editor: "character.cursor.ibeam"
        case .notes: "doc.on.doc"
        case .keywords: "wand.and.stars"
        case .shortcuts: "command.square"
        case .timer: "stopwatch"
        case .export: "square.and.arrow.up"
        case .extensions: "puzzlepiece.extension.fill"
        case .privacy: "eye.slash"
        case .updates: "arrow.down.circle"
        }
    }

    /// Resolves a tab id, title or alias (case-insensitive) used by `WindowServicing.showSettings(tab:)`.
    public init?(routing name: String?) {
        guard let raw = name?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else { return nil }
        let key = raw.filter { $0.isLetter }
        let aliases: [String: SettingsTab] = [
            "theme": .appearance, "themes": .appearance, "visual": .appearance, "icon": .appearance,
            "paper": .appearance, "font": .appearance,
            "writing": .editor, "lists": .editor, "list": .editor, "copypaste": .editor, "copyandpaste": .editor,
            "copy": .editor, "paste": .editor, "clipboard": .editor, "links": .editor, "vim": .editor,
            "storage": .notes, "advanced": .notes, "backups": .notes, "backup": .notes, "void": .notes,
            "sync": .notes, "icloud": .notes, "lock": .notes, "slots": .notes,
            "math": .keywords, "currency": .keywords, "currencies": .keywords, "keyword": .keywords,
            "keyboard": .shortcuts, "hotkey": .shortcuts, "keys": .shortcuts,
            "timers": .timer, "pomodoro": .timer, "extension": .extensions, "network": .privacy,
            "about": .updates, "version": .updates, "update": .updates,
        ]
        if let tab = SettingsTab.allCases.first(where: { $0.rawValue.lowercased() == key }) { self = tab; return }
        if let tab = aliases[key] { self = tab; return }
        return nil
    }
}
