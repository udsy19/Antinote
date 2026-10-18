import Foundation
import ShellKit

/// Window-chrome text and geometry that mirror the reference app.
func registerChromeParityTests() {
    SelfTest.cases.append(("ShellKit.chromeText", {
        check(ChromeText.shortcut(key: "f", command: true, shift: true, option: false, control: false) == "⌘⇧F",
              "modifiers ⌘ then ⇧, key upper-cased")
        check(ChromeText.shortcut(key: "l", command: true, shift: false, option: true, control: true) == "⌘⌥⌃L",
              "⌥ before ⌃")
        check(ChromeText.shortcut(key: "[", command: true, shift: false, option: false, control: false) == "⌘[", "punctuation as is")
        check(ChromeText.shortcut(key: "\u{8}", command: true, shift: false, option: false, control: false) == "⌘⌫", "backspace")
        check(ChromeText.tooltip("New Note", shortcut: "⌘N") == "New Note - ⌘N", "label - shortcut")
        check(ChromeText.tooltip("Export", shortcut: nil) == "Export", "no shortcut, label only")
        check(ChromeText.shortName("Markdown (.md)") == "Markdown", "file-type note dropped")
        check(ChromeText.shortName("Apple Notes") == "Apple Notes", "plain names kept")
    }))

    SelfTest.cases.append(("ShellKit.slotBarLayout", {
        let closed: Double = 254   // 16 × 2 + 9 × 22 + 8 × 3
        check(SlotBarLayout.width(open: nil) == closed, "nine 22 pt planets, 3 pt apart, 16 pt padding")
        check(SlotBarLayout.width(open: 4) == SlotBarLayout.width(open: nil) + 6, "the open planet's frame is 28 pt")
        check(SlotBarLayout.x(of: 0, open: nil) == 16, "first planet after the padding")
        let third: Double = 72   // 16 + 22 + 3 + 28 + 3
        check(SlotBarLayout.x(of: 2, open: 1) == third, "frames after the open slot shift")
        check(SlotBarLayout.frames(open: 8).last == 28, "Pluto can be open")
    }))

    SelfTest.cases.append(("ShellKit.slotBarStates", {
        let states = SlotBarLayout.states(occupied: [0, 1, 4], open: 4)
        check(states.count == 9, "one state per planet")
        check(states[0] == .filled && states[1] == .filled && states[2] == .empty, "slots holding notes are filled, others empty")
        check(states[4] == .open, "the open slot wins over filled")
        check(SlotBarLayout.states(occupied: [], open: nil).allSatisfy { $0 == .empty }, "nothing slotted: all outlines")
        check(SlotBarLayout.states(occupied: Set(0..<9), open: nil).allSatisfy { $0 == .filled }, "all nine slotted")
    }))

    SelfTest.cases.append(("ShellKit.slotBarHitTest", {
        check(SlotBarLayout.slot(atX: 15, open: nil) == nil, "the side padding is no slot")
        check(SlotBarLayout.slot(atX: 16, open: nil) == 0 && SlotBarLayout.slot(atX: 37, open: nil) == 0, "Mercury's column")
        check(SlotBarLayout.slot(atX: 39, open: nil) == 0 && SlotBarLayout.slot(atX: 40, open: nil) == 1, "the gap splits at its middle")
        check(SlotBarLayout.slot(atX: 237, open: nil) == 8, "Pluto's column ends at the padding")
        check(SlotBarLayout.slot(atX: 238, open: nil) == nil, "right padding")
        let afterOpen = SlotBarLayout.x(of: 2, open: 1) + 1
        check(SlotBarLayout.slot(atX: afterOpen, open: 1) == 2, "columns after the wider open slot shift")
        for slot in 0..<9 {
            let mid = SlotBarLayout.x(of: slot, open: 3) + SlotBarLayout.frames(open: 3)[slot] / 2
            check(SlotBarLayout.slot(atX: mid, open: 3) == slot, "each planet's centre hits it (\(slot))")
        }
    }))

    SelfTest.cases.append(("ShellKit.slotBarTip", {
        check(SlotBarLayout.tip(slot: 1, title: "# Aphrodite", assignShortcut: "⌘⌃2") == "Slot 2 — Aphrodite",
              "a slotted note's title, heading marks dropped")
        check(SlotBarLayout.tip(slot: 0, title: "  ", assignShortcut: nil) == "Slot 1 — Untitled", "blank title")
        check(SlotBarLayout.tip(slot: 6, title: nil, assignShortcut: "⌘⌃7") == "Slot 7 — empty\nClick or press ⌘⌃7 to put this note here",
              "an empty slot says how to fill it, with the real shortcut")
        check(SlotBarLayout.tip(slot: 6, title: nil, assignShortcut: nil) == "Slot 7 — empty\nClick to put this note here",
              "no shortcut bound: click only")
    }))

    SelfTest.cases.append(("ShellKit.bottomBarFit", {
        typealias L = BottomBarLayout
        check(L.width(buttons: 5, text: 0) == 202, "5 buttons: 10 + 5 × 30 + 4 × 8 + 10")
        let roomy = L.fit(width: 412, textWidth: 120)
        check(roomy == L.Fit(buttons: 5, textWidth: 120), "a wide window shows everything at full width")
        let standard = L.fit(width: 350, textWidth: 190)
        check(standard.buttons == 5 && standard.textWidth == 140, "350 pt: all buttons, the long date cut to the 140 pt left")
        check(L.width(buttons: standard.buttons, text: standard.textWidth) <= 350, "nothing passes the edge at 350 pt")
        let narrow = L.fit(width: 240, textWidth: 190)
        check(narrow.buttons == 5 && narrow.textWidth == 0, "240 pt: the text goes before any button")
        check(L.fit(width: 250, textWidth: 30) == L.Fit(buttons: 5, textWidth: 30), "short text that fits stays")
        check(L.fit(width: 190, textWidth: 100) == L.Fit(buttons: 4, textWidth: 0), "then Export goes")
        check(L.fit(width: 150, textWidth: 100) == L.Fit(buttons: 3, textWidth: 0), "then First; Delete, Previous, Next stay")
        check(L.fit(width: 350, textWidth: 0).textWidth == 0, "no text, nothing reserved")
        for width in stride(from: 126.0, through: 600, by: 7) {
            let fit = L.fit(width: width, textWidth: 260)
            check(L.width(buttons: fit.buttons, text: fit.textWidth) <= width, "fits at \(width) pt")
            check(fit.textWidth == 0 || fit.textWidth >= L.minTextWidth, "text is either readable or gone at \(width) pt")
        }
    }))
}
