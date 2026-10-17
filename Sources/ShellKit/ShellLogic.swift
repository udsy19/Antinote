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
    private var horizontal: Bool?
    private var fired = false

    public init(sensitivity: Double) { self.sensitivity = sensitivity }

    public static let axisLockDistance = 6.0
    public var threshold: Double { 30 + 170 * min(max(sensitivity, 0), 1) }

    /// `fingerDX` is positive when the fingers move right (independent of natural scrolling).
    public mutating func feed(phase: Phase, fingerDX: Double, fingerDY: Double) -> Outcome {
        switch phase {
        case .began:
            dx = fingerDX; dy = fingerDY; horizontal = nil; fired = false
            return decide()
        case .changed:
            dx += fingerDX; dy += fingerDY
            return decide()
        case .ended:
            let wasHorizontal = horizontal == true
            dx = 0; dy = 0; fired = false
            return wasHorizontal ? .consume : .pass
        case .momentum:
            return horizontal == true ? .consume : .pass
        }
    }

    private mutating func decide() -> Outcome {
        if horizontal == nil {
            guard abs(dx) + abs(dy) >= Self.axisLockDistance else { return .pass }
            horizontal = abs(dx) > abs(dy) * 1.5
        }
        guard horizontal == true else { return .pass }
        guard !fired, abs(dx) >= threshold else { return .consume }
        fired = true
        return .navigate(dx > 0 ? .previous : .next)
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

public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general, appearance, writing, lists, math, copyPaste, keywords, timers, shortcuts, extensions
    case privacy, sync, storage, export, about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .writing: "Writing"
        case .lists: "Lists"
        case .math: "Math"
        case .copyPaste: "Copy & Paste"
        case .keywords: "Keywords"
        case .timers: "Timers"
        case .shortcuts: "Shortcuts"
        case .extensions: "Extensions"
        case .privacy: "Privacy"
        case .sync: "Sync"
        case .storage: "Storage"
        case .export: "Export"
        case .about: "About"
        }
    }

    public var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .writing: "pencil.line"
        case .lists: "checklist"
        case .math: "function"
        case .copyPaste: "doc.on.clipboard"
        case .keywords: "textformat"
        case .timers: "timer"
        case .shortcuts: "command"
        case .extensions: "puzzlepiece.extension"
        case .privacy: "hand.raised"
        case .sync: "icloud"
        case .storage: "externaldrive"
        case .export: "square.and.arrow.up"
        case .about: "info.circle"
        }
    }

    /// Resolves a tab id, title or alias (case-insensitive) used by `WindowServicing.showSettings(tab:)`.
    public init?(routing name: String?) {
        guard let raw = name?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else { return nil }
        let key = raw.filter { $0.isLetter }
        let aliases: [String: SettingsTab] = [
            "copypaste": .copyPaste, "copyandpaste": .copyPaste, "paste": .copyPaste, "clipboard": .copyPaste,
            "theme": .appearance, "themes": .appearance, "visual": .appearance, "icon": .appearance,
            "keyboard": .shortcuts, "hotkey": .shortcuts, "keys": .shortcuts,
            "advanced": .storage, "notes": .storage, "backups": .storage, "backup": .storage, "void": .storage,
            "icloud": .sync, "network": .privacy, "lock": .privacy, "currency": .math, "currencies": .math,
            "timer": .timers, "pomodoro": .timers, "list": .lists, "keyword": .keywords, "extension": .extensions,
        ]
        if let tab = SettingsTab.allCases.first(where: { $0.rawValue.lowercased() == key }) { self = tab; return }
        if let tab = aliases[key] { self = tab; return }
        return nil
    }
}
