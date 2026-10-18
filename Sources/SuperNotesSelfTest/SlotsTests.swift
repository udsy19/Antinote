import AppKit
import SuperNotesCore
import ShellKit

/// Slots: when the planets bar shows (never while typing), moving between the slots in use, and the shell driven
/// offscreen — opening a slot and coming back keeps the deck note and its caret, swipes stop at the ends without
/// creating anything, Put in Slot / Remove from Slot carry the caret and undo with ⌘Z.
func registerSlotsTests() {
    SelfTest.cases.append(("ShellKit.slotBarVisibility", {
        typealias V = SlotBarVisibility
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

        var v = V(alwaysShow: false)
        check(!v.isVisible(at: t0) && v.nextChange(after: t0) == nil, "hidden by default, nothing pending")

        // Hover: the pointer has to rest in the strip for the dwell; passing through shows nothing.
        v.handle(.pointer(inZone: true), at: t0)
        check(!v.isVisible(at: at(0.1)), "a pointer passing through the strip shows nothing")
        check(v.nextChange(after: t0) == at(V.hoverDwell), "the dwell is pending")
        v.handle(.pointer(inZone: false), at: at(0.1))
        check(!v.isVisible(at: at(1)) && v.nextChange(after: at(0.1)) == nil, "left before the dwell: still hidden, nothing pending")
        v.handle(.pointer(inZone: true), at: at(1))
        check(!v.isVisible(at: at(1.2)) && v.isVisible(at: at(1.25)), "up once the pointer has rested for 250 ms")
        v.handle(.pointer(inZone: true), at: at(2))
        check(v.isVisible(at: at(2)), "moving within the strip keeps it up")
        v.handle(.pointer(inZone: false), at: at(3))
        check(!v.isVisible(at: at(3)), "down as soon as the pointer leaves")

        // Typing: never visible, however it came up; the pointer must come back into the strip.
        v.handle(.pointer(inZone: true), at: at(4))
        check(v.isVisible(at: at(5)), "up again after a dwell")
        v.handle(.keystroke, at: at(5))
        check(!v.isVisible(at: at(5)) && !v.isVisible(at: at(60)), "a keystroke hides it for good, pointer still in the strip")
        check(v.nextChange(after: at(5)) == nil, "no timer brings it back by itself")
        v.handle(.pointer(inZone: true), at: at(6))
        check(!v.isVisible(at: at(6)) && v.isVisible(at: at(6.25)), "moving the pointer in the strip again starts a fresh dwell")

        // Navigation: 2 s after a slot is used, wherever the pointer is; typing cuts it short.
        v = V(alwaysShow: false)
        v.handle(.navigated, at: t0)
        check(v.isVisible(at: at(0)) && v.isVisible(at: at(1.9)) && !v.isVisible(at: at(2)), "shown for 2 s after navigating")
        check(v.nextChange(after: t0) == at(V.navigationLinger), "the linger is pending")
        v.handle(.navigated, at: at(1))
        check(v.isVisible(at: at(2.5)) && !v.isVisible(at: at(3)), "another move restarts the linger")
        v.handle(.keystroke, at: at(1.5))
        check(!v.isVisible(at: at(1.5)) && !v.isVisible(at: at(1.6)), "typing takes it down at once")

        // Always show: on, except while typing; the pointer or 2 s of quiet bring it back.
        v = V(alwaysShow: true)
        check(v.isVisible(at: t0) && v.nextChange(after: t0) == nil, "always-show: up at rest")
        v.handle(.keystroke, at: t0)
        check(!v.isVisible(at: at(0.5)) && !v.isVisible(at: at(1.99)), "always-show still hides while typing")
        check(v.nextChange(after: t0) == at(V.typingRest), "it comes back by itself after the rest")
        v.handle(.keystroke, at: at(1))
        check(!v.isVisible(at: at(2.5)) && v.isVisible(at: at(3)), "each keystroke restarts the rest")
        v.handle(.keystroke, at: at(4))
        v.handle(.pointer(inZone: true), at: at(4.1))
        check(v.isVisible(at: at(4.1)), "the pointer coming into the strip brings it straight back")
        v.handle(.keystroke, at: at(5))
        v.handle(.alwaysShow(false), at: at(5))
        check(!v.isVisible(at: at(10)) && v.nextChange(after: at(5)) == nil, "switching always-show off while hidden by typing: stays down")
        v.handle(.alwaysShow(true), at: at(11))
        check(v.isVisible(at: at(11)), "switching it on while quiet brings it up")
    }))

    SelfTest.cases.append(("ShellKit.slotNavigator", {
        let used: Set<Int> = [0, 4, 7]
        check(SlotNavigator.step(from: 0, occupied: used, direction: .next) == .open(slot: 4), "next skips the empty slots")
        check(SlotNavigator.step(from: 4, occupied: used, direction: .previous) == .open(slot: 0), "previous likewise")
        check(SlotNavigator.step(from: 7, occupied: used, direction: .next) == .stay(reason: "Last slot"), "stops at the last slot in use")
        check(SlotNavigator.step(from: 0, occupied: used, direction: .previous) == .stay(reason: "First slot"), "and at the first")
        check(SlotNavigator.step(from: nil, occupied: used, direction: .next) == .open(slot: 0), "from the deck, Next Slot opens the first")
        check(SlotNavigator.step(from: nil, occupied: used, direction: .previous) == .open(slot: 7), "Previous Slot the last")
        check(SlotNavigator.step(from: 2, occupied: used, direction: .next) == .open(slot: 4), "from a slot no longer in use: the next one")
        check(SlotNavigator.step(from: 4, occupied: [4], direction: .next) == .stay(reason: "Last slot")
              && SlotNavigator.step(from: 4, occupied: [4], direction: .previous) == .stay(reason: "First slot"), "one slot: both ends")
        check(SlotNavigator.step(from: nil, occupied: [], direction: .next) == nil, "no slots in use: nothing to open")
        check(SlotNavigator.step(from: 0, occupied: [0, 12], direction: .next) == .stay(reason: "Last slot"), "invalid slots are ignored")
    }))

    SelfTest.cases.append(("ShellKit.slotsShell", {
        MainActor.assumeIsolated {
            let b = Bench()
            defer { b.cleanup() }
            let hermes = b.store.create(content: "# Hermes\nSlot one.")
            b.store.setSlot(0, for: hermes.id)
            let zeus = b.store.create(content: "# Zeus\nSlot five.")
            b.store.setSlot(4, for: zeus.id)
            _ = b.store.create(content: "an older note")
            let front = b.store.create(content: "the front note, being written")
            WindowPreview.reload()
            _ = WindowPreview.frameView(revealed: false, slotBar: .hidden)
            let window = WindowPreview.window
            check(WindowPreview.currentNoteID == front.id && WindowPreview.openSlot == nil, "starts on the deck's front note")
            check(!WindowPreview.isSlotBarShown, "the slot bar is hidden at rest")
            guard let deckText = window.firstResponder as? NSTextView else { return check(false, "the note's text has the focus") }
            deckText.setSelectedRange(NSRange(location: 9, length: 0))
            let notes = b.store.deck.count

            // Open a slot: the slotted note, focused, with the bar up for the moment; the deck note waits as it was.
            WindowPreview.openSlot(0)
            check(WindowPreview.currentNoteID == hermes.id && WindowPreview.openSlot == 0, "Go to Slot 1 shows Hermes")
            check(WindowPreview.isSlotBarShown, "the bar shows while moving between slots")
            guard let slotText = window.firstResponder as? NSTextView, slotText !== deckText else {
                return check(false, "the slotted note's text has the focus")
            }
            check(slotText.string.hasPrefix("# Hermes"), "the focus is in the slotted note")
            check(WindowPreview.escapeGoesBack, "Esc means Back to Notes here")

            // Swiping moves through the slots in use only and stops at the ends; nothing is created.
            WindowPreview.navigate(.next)
            check(WindowPreview.openSlot == 4 && WindowPreview.currentNoteID == zeus.id, "next: slots 2–4 are empty, so Zeus")
            WindowPreview.navigate(.next)
            check(WindowPreview.openSlot == 4, "past the last slot it stays")
            WindowPreview.navigate(.previous)
            WindowPreview.navigate(.previous)
            check(WindowPreview.openSlot == 0 && b.store.deck.count == notes, "back to the first and no further; no note was created")

            // Back: the very note and caret left behind.
            WindowPreview.backToNotes()
            check(WindowPreview.currentNoteID == front.id && WindowPreview.openSlot == nil, "Back to Notes returns to the deck note")
            check(window.firstResponder === deckText && deckText.selectedRange() == NSRange(location: 9, length: 0),
                  "same text view, caret where it was: \(deckText.selectedRange())")
            check(!WindowPreview.escapeGoesBack, "Esc is the note's again on the deck")
            WindowPreview.openSlot(2)
            check(WindowPreview.openSlot == nil && WindowPreview.currentNoteID == front.id, "an empty slot opens nothing")

            // Put in Slot carries the note and its caret into the slot pane; ⌘Z puts it back.
            WindowPreview.putInSlot(1)
            check(b.store.note(front.id)?.slot == 1 && WindowPreview.openSlot == 1 && WindowPreview.currentNoteID == front.id,
                  "the note is in slot 2 and still in front")
            check((window.firstResponder as? NSTextView)?.selectedRange() == NSRange(location: 9, length: 0), "caret carried into the slot")
            check(Bench.menuTitle("undo:", in: window) == "Undo Move to Slot", "⌘Z offers to undo: \(Bench.menuTitle("undo:", in: window))")
            check(window.firstResponder?.tryToPerform(NSSelectorFromString("undo:"), with: nil) == true, "undo reaches the shell")
            check(b.store.note(front.id)?.slot == nil && WindowPreview.openSlot == nil && WindowPreview.currentNoteID == front.id,
                  "undone: back in the deck, still in front")

            // Replacing an occupied slot pushes its note to the deck, no question asked; ⌘Z restores both.
            WindowPreview.putInSlot(0)
            check(b.store.note(front.id)?.slot == 0 && b.store.note(hermes.id)?.slot == nil, "Hermes went back to the deck")
            check(WindowPreview.openSlot == 0 && WindowPreview.currentNoteID == front.id, "the moved note is in front, in slot 1")
            WindowPreview.putInSlot(0)
            check(b.store.note(front.id)?.slot == 0, "putting it in its own slot does nothing")
            _ = window.firstResponder?.tryToPerform(NSSelectorFromString("undo:"), with: nil)
            check(b.store.note(front.id)?.slot == nil && b.store.note(hermes.id)?.slot == 0, "undone: Hermes is back in slot 1")

            // Remove from Slot returns the note to the deck, and ⌘Z puts it back in its slot.
            WindowPreview.openSlot(4)
            WindowPreview.removeFromSlot()
            check(b.store.note(zeus.id)?.slot == nil && WindowPreview.openSlot == nil && WindowPreview.currentNoteID == zeus.id,
                  "Zeus is in the deck and in front")
            _ = window.firstResponder?.tryToPerform(NSSelectorFromString("undo:"), with: nil)
            check(b.store.note(zeus.id)?.slot == 4 && WindowPreview.openSlot == 4, "undone: Zeus is back in slot 5")
            WindowPreview.backToNotes()

            // The bar in the window: typing hides it even with always-show on; a resting pointer brings it up.
            _ = WindowPreview.frameView(revealed: false, slotBar: .typing)
            check(!WindowPreview.isSlotBarShown, "hidden while typing")
            _ = WindowPreview.frameView(revealed: false, slotBar: .hovering)
            check(WindowPreview.isSlotBarShown, "up once the pointer has rested along the bottom")
            Defaults[.alwaysShowSlotsBar] = true
            _ = WindowPreview.frameView(revealed: false, slotBar: .hidden)
            check(WindowPreview.isSlotBarShown, "always-show: up")
            _ = WindowPreview.frameView(revealed: false, slotBar: .typing)
            check(!WindowPreview.isSlotBarShown, "always-show: still down while typing")
            Defaults.reset(.alwaysShowSlotsBar)
            _ = WindowPreview.frameView(revealed: false, slotBar: .hidden)
            check(!WindowPreview.isSlotBarShown, "off again: hidden at rest")
        }
    }))
}
