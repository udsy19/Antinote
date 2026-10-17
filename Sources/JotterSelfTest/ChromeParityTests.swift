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
}
