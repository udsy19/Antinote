import Foundation

// Pure, UI-free rules behind the shell (covered by SuperNotesSelfTest).

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

public enum SlotStep: Equatable, Sendable {
    case open(slot: Int)
    /// Already at that end of the slots; `reason` is shown as a HUD ("First slot" / "Last slot").
    case stay(reason: String)
}

/// Moving between the slots holding a note, in slot order: a swipe or Next/Previous Slot never lands on an empty
/// slot and never falls out into the deck; at either end it stays put.
public enum SlotNavigator {
    /// From `current` (nil = coming from the deck: Next Slot opens the first slot in use, Previous Slot the last)
    /// in `direction` (`.next` = the higher slot). Nil when no slot holds a note.
    public static func step(from current: Int?, occupied: Set<Int>, direction: SwipeDirection) -> SlotStep? {
        let used = occupied.filter(SlotBoard.isValid).sorted()
        guard !used.isEmpty else { return nil }
        guard let current else { return .open(slot: direction == .next ? used[0] : used[used.count - 1]) }
        switch direction {
        case .next:
            return used.first { $0 > current }.map { .open(slot: $0) } ?? .stay(reason: "Last slot")
        case .previous:
            return used.last { $0 < current }.map { .open(slot: $0) } ?? .stay(reason: "First slot")
        }
    }
}

// MARK: - Slot bar visibility

/// When the planets bar is on screen. It is hidden by default and never while the user types: it comes up when the
/// pointer rests in the bottom strip of the window for `hoverDwell`, for `navigationLinger` after a slot is used,
/// or all the time with "Always show the slot bar" — and even then a keystroke takes it down until the pointer
/// comes back into the strip or `typingRest` has passed since the last keystroke. Time is passed in, so the rules
/// are checked without waiting (`ShellKit.slotBarVisibility`).
public struct SlotBarVisibility: Equatable, Sendable {
    /// Height of the strip along the bottom of the window where a resting pointer brings the bar up.
    public static let hoverZone: Double = 28
    public static let hoverDwell: TimeInterval = 0.25
    public static let navigationLinger: TimeInterval = 2
    public static let typingRest: TimeInterval = 2
    public static let fadeDuration: TimeInterval = 0.15

    public private(set) var alwaysShow: Bool
    private var pointerInZone = false
    /// When the pointer settled in the strip (counting towards the dwell); nil while it is elsewhere.
    private var dwellStart: Date?
    /// The keystroke that hid the bar; nil once the pointer came back or the bar may show again.
    private var typedAt: Date?
    private var navigatedAt: Date?

    public enum Event: Equatable, Sendable {
        /// The pointer moved; `inZone` while it is in the bottom strip or on the shown bar.
        case pointer(inZone: Bool)
        /// A plain keystroke went into the note.
        case keystroke
        /// A slot was opened, left or changed from the keyboard, the bar or a swipe.
        case navigated
        case alwaysShow(Bool)
    }

    public init(alwaysShow: Bool) { self.alwaysShow = alwaysShow }

    public mutating func handle(_ event: Event, at now: Date) {
        switch event {
        case .pointer(let inZone):
            if inZone {
                // Entering the strip (or moving in it after typing) starts the dwell afresh.
                if !pointerInZone || typedAt != nil { dwellStart = now }
                pointerInZone = true
                typedAt = nil
            } else {
                pointerInZone = false
                dwellStart = nil
            }
        case .keystroke:
            typedAt = now
            dwellStart = nil
            navigatedAt = nil
        case .navigated:
            navigatedAt = now
            typedAt = nil
        case .alwaysShow(let on):
            alwaysShow = on
        }
    }

    public func isVisible(at now: Date) -> Bool {
        if let typedAt {
            // Typing hides the bar; with always-show it comes back by itself once typing has stopped.
            return alwaysShow && now.timeIntervalSince(typedAt) >= Self.typingRest
        }
        if alwaysShow { return true }
        if let navigatedAt, now.timeIntervalSince(navigatedAt) < Self.navigationLinger { return true }
        if pointerInZone, let dwellStart, now.timeIntervalSince(dwellStart) >= Self.hoverDwell { return true }
        return false
    }

    /// The next moment `isVisible` may change by time alone (the dwell ending, the linger or the typing rest
    /// running out); nil when only an event can change it.
    public func nextChange(after now: Date) -> Date? {
        var times: [Date] = []
        if let typedAt {
            if alwaysShow { times.append(typedAt.addingTimeInterval(Self.typingRest)) }
        } else if !alwaysShow {
            if let navigatedAt { times.append(navigatedAt.addingTimeInterval(Self.navigationLinger)) }
            if pointerInZone, let dwellStart { times.append(dwellStart.addingTimeInterval(Self.hoverDwell)) }
        }
        return times.filter { $0 > now }.min()
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

    /// The slot whose column holds `x` (bar coordinates); the gaps between planets belong to the nearer one.
    public static func slot(atX x: Double, open: Int?) -> Int? {
        let f = frames(open: open)
        guard x >= padding, x < width(open: open) - padding else { return nil }
        for slot in 0..<f.count where x < Self.x(of: slot, open: open) + f[slot] + spacing / 2 { return slot }
        return f.count - 1
    }

    /// How a planet is drawn: the open slot in the accent colour; slots holding a note filled; empty slots as
    /// faint outlines.
    public enum State: Equatable, Sendable { case empty, filled, open }

    public static func states(occupied: Set<Int>, open: Int?) -> [State] {
        (0..<SlotBoard.count).map { $0 == open ? .open : occupied.contains($0) ? .filled : .empty }
    }

    /// A note's title as the slot bar names it: a heading's "#" marks dropped, "Untitled" when blank.
    public static func cleanTitle(_ title: String) -> String {
        let trimmed = title.drop { $0 == "#" }.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    /// The hover tip: "Slot 2 — Groceries · ⌃⌘2" for a slot holding a note (its Go to Slot shortcut, when it has
    /// one); for the open slot, how to get back; for an empty one, what a click (or the Put in Slot shortcut) does.
    public static func tip(slot: Int, title: String?, isOpen: Bool = false, openShortcut: String?, assignShortcut: String?) -> String {
        let name = "Slot \(slot + 1)"
        if let title {
            if isOpen { return "\(name) — \(cleanTitle(title)) · open\nClick or press Esc to go back to your notes" }
            return "\(name) — \(cleanTitle(title))" + (openShortcut.map { " · \($0)" } ?? "")
        }
        let how = assignShortcut.map { "Click or press \($0)" } ?? "Click"
        return "\(name) — empty\n\(how) to put this note here"
    }

    /// The label shown for a moment when a slot opens: "Slot 3 · Groceries".
    public static func label(slot: Int, title: String) -> String { "Slot \(slot + 1) · \(cleanTitle(title))" }
}

/// What fits in the bottom bar (Delete · date and position · Previous · Next · First · Export), so nothing is ever
/// clipped: 30 pt buttons 8 pt apart, 10 pt from the sides; the text sits between Delete and Previous with 8 pt on
/// each side. As the window narrows the text is cut short (with "…"), then dropped below `minTextWidth`; then
/// Export goes, then First. Delete, Previous and Next always stay.
public enum BottomBarLayout {
    public static let sideInset = 10.0
    public static let spacing = 8.0
    public static let button = 30.0
    public static let minTextWidth = 48.0

    public struct Fit: Equatable, Sendable {
        /// 3…5: Delete, Previous and Next, then First, then Export.
        public var buttons: Int
        /// The text's width; 0 when it is hidden.
        public var textWidth: Double
        public var showsFirst: Bool { buttons >= 4 }
        public var showsExport: Bool { buttons >= 5 }
        public init(buttons: Int, textWidth: Double) { self.buttons = buttons; self.textWidth = textWidth }
    }

    /// The width `buttons` buttons and `text` points of text need.
    public static func width(buttons: Int, text: Double) -> Double {
        2 * sideInset + Double(buttons) * button + Double(buttons - 1) * spacing + (text > 0 ? text + spacing : 0)
    }

    /// The items that fit a bar `width` wide whose text wants `textWidth` points.
    public static func fit(width: Double, textWidth: Double) -> Fit {
        let room = width - self.width(buttons: 5, text: 0) - spacing
        if textWidth > 0, room >= min(textWidth, minTextWidth) { return Fit(buttons: 5, textWidth: min(textWidth, room)) }
        for n in [5, 4] where width >= self.width(buttons: n, text: 0) { return Fit(buttons: n, textWidth: 0) }
        return Fit(buttons: 3, textWidth: 0)
    }
}

// MARK: - Dropdown window

/// Where the window goes when it drops down from the menu bar.
public enum DropdownLayout {
    /// `size` (Settings → General → Dropdown window size) kept at least `minimum` and inside `visible`, centred
    /// under `anchor` (the status item), 4 pt below it and at least 6 pt from the screen's sides.
    public static func frame(size: CGSize, minimum: CGSize, anchor: CGRect, visible: CGRect) -> CGRect {
        let width = min(max(size.width, minimum.width), visible.width - 12)
        let height = min(max(size.height, minimum.height), anchor.minY - 4 - visible.minY)
        let x = min(max(anchor.midX - width / 2, visible.minX + 6), visible.maxX - width - 6)
        return CGRect(x: x, y: anchor.minY - 4 - height, width: width, height: height)
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
