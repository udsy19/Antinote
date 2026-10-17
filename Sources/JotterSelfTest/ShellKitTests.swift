import Foundation
import JotterCore
import ShellKit

/// Append cases with `SelfTest.cases.append(("name", { check(..., "msg") }))`.
func registerShellKitTests() {
    SelfTest.cases.append(("ShellKit.swipeAccumulator", {
        var s = SwipeAccumulator(sensitivity: 0)          // threshold 30
        check(s.threshold == 30, "lowest sensitivity threshold")
        check(SwipeAccumulator(sensitivity: 1).threshold == 200, "highest sensitivity threshold")
        check(SwipeAccumulator(sensitivity: 5).threshold == 200, "sensitivity is clamped")
        check(s.feed(phase: .began, fingerDX: 2, fingerDY: 0) == .pass, "below axis-lock distance passes")
        check(s.feed(phase: .changed, fingerDX: 10, fingerDY: 1) == .consume, "horizontal gesture is consumed")
        check(s.feed(phase: .changed, fingerDX: 20, fingerDY: 0) == .navigate(.previous), "fingers right → previous")
        check(s.feed(phase: .changed, fingerDX: 50, fingerDY: 0) == .consume, "fires only once per gesture")
        check(s.feed(phase: .momentum, fingerDX: 40, fingerDY: 0) == .consume, "momentum of a swipe is swallowed")
        check(s.feed(phase: .ended, fingerDX: 0, fingerDY: 0) == .consume, "end of horizontal gesture consumed")

        check(s.feed(phase: .began, fingerDX: -8, fingerDY: 0) == .consume, "new gesture locks horizontal")
        check(s.feed(phase: .changed, fingerDX: -25, fingerDY: 0) == .navigate(.next), "fingers left → next")
        _ = s.feed(phase: .ended, fingerDX: 0, fingerDY: 0)

        check(s.feed(phase: .began, fingerDX: 3, fingerDY: 10) == .pass, "vertical scroll passes")
        check(s.feed(phase: .changed, fingerDX: 80, fingerDY: 0) == .pass, "axis stays vertical for the gesture")
        check(s.feed(phase: .momentum, fingerDX: 80, fingerDY: 0) == .pass, "vertical momentum passes")

        var firm = SwipeAccumulator(sensitivity: 1)
        _ = firm.feed(phase: .began, fingerDX: 10, fingerDY: 0)
        check(firm.feed(phase: .changed, fingerDX: 150, fingerDY: 0) == .consume, "firm needs a longer swipe")
        check(firm.feed(phase: .changed, fingerDX: 45, fingerDY: 0) == .navigate(.previous), "firm fires at 200")
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
                                                     "Timer", "Export", "Extensions", "Privacy", "Updates"], "eleven tabs in order")
    }))
}
