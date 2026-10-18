import Foundation
import SuperNotesCore
import ShellKit

/// Append cases with `SelfTest.cases.append(("name", { check(..., "msg") }))`.
func registerShellKitTests() {
    SelfTest.cases.append(("ShellKit.swipeAccumulator", {
        check(SwipeAccumulator(sensitivity: 0).threshold == 0, "lightest: any horizontal start")
        check(SwipeAccumulator(sensitivity: 1).threshold == 30, "firmest threshold")
        check(SwipeAccumulator(sensitivity: 5).threshold == 30, "sensitivity is clamped")

        var s = SwipeAccumulator(sensitivity: 0)
        check(s.feed(phase: .began, fingerDX: 3, fingerDY: 1) == .navigate(.previous), "fires on the first horizontal move")
        check(s.feed(phase: .changed, fingerDX: 50, fingerDY: 0) == .consume, "once per gesture")
        check(s.feed(phase: .ended, fingerDX: 0, fingerDY: 0) == .consume, "end of the swipe is swallowed")
        check(s.feed(phase: .momentum, fingerDX: 40, fingerDY: 0) == .consume, "momentum of the swipe is swallowed")

        check(s.feed(phase: .began, fingerDX: 0, fingerDY: 0) == .pass, "a still touch (may-begin) waits")
        check(s.feed(phase: .changed, fingerDX: -2, fingerDY: 0) == .navigate(.next), "fingers left → next")
        _ = s.feed(phase: .ended, fingerDX: 0, fingerDY: 0)

        check(s.feed(phase: .began, fingerDX: 1, fingerDY: 6) == .pass, "vertical start scrolls")
        check(s.feed(phase: .changed, fingerDX: 80, fingerDY: 0) == .pass, "and stays a scroll")
        _ = s.feed(phase: .ended, fingerDX: 0, fingerDY: 0)
        check(s.feed(phase: .momentum, fingerDX: 80, fingerDY: 0) == .pass, "vertical momentum passes")

        // Back-to-back swipes each switch once.
        check(s.feed(phase: .began, fingerDX: 4, fingerDY: 0) == .navigate(.previous), "second swipe")
        _ = s.feed(phase: .ended, fingerDX: 0, fingerDY: 0)
        check(s.feed(phase: .began, fingerDX: 4, fingerDY: 0) == .navigate(.previous), "third swipe")

        var firm = SwipeAccumulator(sensitivity: 1)
        check(firm.feed(phase: .began, fingerDX: 10, fingerDY: 0) == .consume, "firm: still deciding")
        check(firm.feed(phase: .changed, fingerDX: 25, fingerDY: 0) == .navigate(.previous), "firm fires past 30")
        var hesitant = SwipeAccumulator(sensitivity: 1)
        _ = hesitant.feed(phase: .began, fingerDX: 2, fingerDY: 0)
        _ = hesitant.feed(phase: .changed, fingerDX: 2, fingerDY: 0)
        check(hesitant.feed(phase: .changed, fingerDX: 2, fingerDY: 0) == .pass, "slow drift is left to scroll")
    }))

    SelfTest.cases.append(("ShellKit.deckNavigator", {
        check(DeckNavigator.step(from: 0, count: 5, direction: .previous, currentIsEmpty: false) == .show(index: 1), "older")
        check(DeckNavigator.step(from: 3, count: 5, direction: .next, currentIsEmpty: false) == .show(index: 2), "newer")
        check(DeckNavigator.step(from: 0, count: 5, direction: .next, currentIsEmpty: false) == .createNew,
              "past the newest creates a note")
        check(DeckNavigator.step(from: 0, count: 5, direction: .next, currentIsEmpty: true) == .stay(reason: "Already at latest"),
              "no second empty note")
        check(DeckNavigator.step(from: 4, count: 5, direction: .previous, currentIsEmpty: false)
              == .stay(reason: "This is the oldest note"), "stops at the oldest")
        check(DeckNavigator.step(from: 9, count: 3, direction: .next, currentIsEmpty: false) == .show(index: 1),
              "out-of-range index is clamped")
        check(DeckNavigator.step(from: 0, count: 0, direction: .previous, currentIsEmpty: true) == .createNew,
              "empty deck creates a note")
        check(DeckNavigator.isBlank(" \n\t "), "whitespace is blank")
        check(!DeckNavigator.isBlank(" x "), "text is not blank")
    }))

    SelfTest.cases.append(("ShellKit.slotBoard", {
        let a = UUID(), b = UUID(), c = UUID()
        var board = SlotBoard(notes: [(a, 0), (b, nil), (c, 12)])
        check(board.slot(of: a) == 0 && board.slot(of: c) == nil, "invalid slots ignored")
        check(board.firstFree == 1, "first free slot")
        var changes = board.assign(b, to: 0)
        check(changes.count == 2 && changes[0].id == a && changes[0].slot == nil && changes[1].id == b && changes[1].slot == 0,
              "occupant pushed back to the deck")
        changes = board.assign(b, to: 4)
        check(changes.count == 1 && board.slot(of: b) == 4 && board.occupants[0] == nil, "moving frees the old slot")
        changes = board.assign(b, to: 4)
        check(changes.count == 1 && changes[0].slot == nil && board.isEmpty, "same slot toggles off")
        check(board.assign(a, to: 9).isEmpty && board.assign(a, to: -1).isEmpty, "out-of-range slots rejected")
        _ = board.assign(a, to: 8)
        check(board.remove(a).first?.slot == nil && board.isEmpty, "remove from slot")
        check(board.remove(a).isEmpty, "removing an unslotted note is a no-op")
    }))

    SelfTest.cases.append(("ShellKit.relockSession", {
        let id = UUID(), t0 = Date(timeIntervalSince1970: 1_000_000)
        var r = RelockSession()
        check(!r.isUnlocked(id, now: t0, minutes: 5), "locked by default")
        r.unlock(id, at: t0)
        r.setFocused(true, at: t0)
        check(r.isUnlocked(id, now: t0.addingTimeInterval(3600), minutes: 5), "never expires while in focus")
        r.setFocused(false, at: t0.addingTimeInterval(3600))
        check(r.isUnlocked(id, now: t0.addingTimeInterval(3600 + 299), minutes: 5), "still open within timeout")
        check(!r.isUnlocked(id, now: t0.addingTimeInterval(3600 + 300), minutes: 5), "relocks after timeout")
        r.unlock(id, at: t0)
        check(!r.isUnlocked(id, now: t0, minutes: 0), "0 minutes relocks as soon as focus leaves")
        r.unlock(id, at: t0)
        r.lock(id)
        check(!r.isUnlocked(id, now: t0, minutes: 60), "explicit lock")
        r.unlock(id, at: t0)
        r.relockAll()
        check(r.unlocked.isEmpty, "relock all")
    }))

    SelfTest.cases.append(("ShellKit.inactivity", {
        let now = Date()
        check(!InactivityPolicy.shouldStartFresh(lastHidden: now.addingTimeInterval(-9999), now: now, minutes: 0), "0 = never")
        check(!InactivityPolicy.shouldStartFresh(lastHidden: nil, now: now, minutes: 5), "never hidden")
        check(!InactivityPolicy.shouldStartFresh(lastHidden: now.addingTimeInterval(-299), now: now, minutes: 5), "too soon")
        check(InactivityPolicy.shouldStartFresh(lastHidden: now.addingTimeInterval(-300), now: now, minutes: 5), "after timeout")
    }))

    SelfTest.cases.append(("ShellKit.settingsRouting", {
        check(SettingsTab(routing: "general") == .general, "raw value")
        check(SettingsTab(routing: "Copy & Paste") == .editor, "old tab title routes to its new home")
        check(SettingsTab(routing: "copyPaste") == .editor, "camel case")
        check(SettingsTab(routing: "advanced") == .notes && SettingsTab(routing: "storage") == .notes, "storage aliases")
        check(SettingsTab(routing: "math") == .keywords && SettingsTab(routing: "about") == .updates, "moved tabs")
        check(SettingsTab(routing: "HOTKEY") == .shortcuts, "case-insensitive alias")
        check(SettingsTab(routing: nil) == nil && SettingsTab(routing: " ") == nil, "empty")
        check(SettingsTab(routing: "nonsense") == nil, "unknown")
        check(SettingsTab.allCases.allSatisfy { SettingsTab(routing: $0.title) == $0 }, "every title routes to itself")
        check(SettingsTab.allCases.map(\.title) == ["General", "Appearance", "Editor", "Notes", "Keywords", "Shortcuts",
                                                     "Timer", "Export", "Extensions", "AI", "Privacy", "Updates"], "twelve tabs in order")
        check(SettingsTab(routing: "model") == .ai && SettingsTab(routing: "AI") == .ai, "AI aliases")
    }))
}
