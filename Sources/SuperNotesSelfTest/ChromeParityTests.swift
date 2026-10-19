import AppKit
import SuperNotesCore
import ShellKit
import ToolsKit

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
        check(SlotBarLayout.tip(slot: 1, title: "# Aphrodite", openShortcut: "⌘⌃2", assignShortcut: "⌘⌥2") == "Slot 2 — Aphrodite · ⌘⌃2",
              "a slotted note's title, heading marks dropped, with its Go to Slot shortcut")
        check(SlotBarLayout.tip(slot: 0, title: "  ", openShortcut: nil, assignShortcut: nil) == "Slot 1 — Untitled", "blank title, no shortcut")
        check(SlotBarLayout.tip(slot: 1, title: "# Aphrodite", isOpen: true, openShortcut: "⌘⌃2", assignShortcut: nil)
              == "Slot 2 — Aphrodite · open\nClick or press Esc to go back to your notes", "the open slot says how to get back")
        check(SlotBarLayout.tip(slot: 6, title: nil, openShortcut: "⌘⌃7", assignShortcut: "⌘⌥7") == "Slot 7 — empty\nClick or press ⌘⌥7 to put this note here",
              "an empty slot says how to fill it, with the real shortcut")
        check(SlotBarLayout.tip(slot: 6, title: nil, openShortcut: nil, assignShortcut: nil) == "Slot 7 — empty\nClick to put this note here",
              "no shortcut bound: click only")
        check(SlotBarLayout.label(slot: 2, title: "## Groceries ") == "Slot 3 · Groceries", "the opening label")
        check(SlotBarLayout.cleanTitle("#") == "Untitled", "a bare heading mark is untitled")
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

    SelfTest.cases.append(("ShellKit.chromeMetrics", {
        typealias M = ChromeMetrics
        check(M.button == 30 && M.glyph == 22 && M.sideInset == 10 && M.spacing == 8 && M.row == 20 && M.cornerRadius == 5,
              "one size system for every chrome button")
        let lights = M.trafficLights
        check(M.groupGap == 16 && M.leadingInset == lights.end + 16, "the top bar's left group starts two gaps after the zoom button")
        check(lights.start >= 7 && lights.end >= 61 && lights.end - lights.start >= 54, "the lights were measured from the window: \(lights)")
        check(BottomBarLayout.button == 30 && BottomBarLayout.sideInset == 10 && BottomBarLayout.spacing == 8, "the bottom bar follows it")
        check(M.buttons(3, from: M.leadingInset, y: 5).map { $0.minX - M.leadingInset } == [0, 38, 76], "Settings, Search, Typing")
        check(M.topBarHeight == M.row + M.button / 2 && M.bottomBarHeight == 2 * M.row, "each strip covers its row")
        check(M.leftButtonsFitting(width: 350, left: 3, right: 2) == 3, "350 pt: Settings, Search and Typing beside New Note and Pin")
        let full = M.topBarWidth(left: 3, right: 2)
        check(full == M.leadingInset + 3 * 30 + 2 * 8 + 8 + 2 * 30 + 8 + 10, "the full top bar: \(full) pt")
        check(M.leftButtonsFitting(width: full, left: 3, right: 2) == 3 && M.leftButtonsFitting(width: full - 1, left: 3, right: 2) == 2,
              "under \(full) pt Typing gives way")
        check(M.topBarWidth(left: 2, right: 2) <= 240, "Settings and Search still fit the narrowest window beside New Note and Pin")
        check(M.leftButtonsFitting(width: 100, left: 3, right: 2) == 2, "Settings and Search always stay")
        let classic = M.trafficLights
        M.trafficLights = M.TrafficLights(start: 7, end: 61)
        check(M.leadingInset == 77 && M.topBarWidth(left: 3, right: 2) == 269, "macOS 14 / 15 lights: the group starts at 77, Typing goes under 269 pt")
        M.trafficLights = M.TrafficLights(start: 9, end: 69)
        check(M.leadingInset == 85 && M.topBarWidth(left: 3, right: 2) == 277, "macOS 26 lights: the group starts at 85, Typing goes under 277 pt")
        M.trafficLights = classic
        check(SearchToolbarLayout.showsLabels(width: 350, labelled: 220, right: 80), "350 pt: both Search capsules with labels")
        check(!SearchToolbarLayout.showsLabels(width: 240, labelled: 220, right: 80), "240 pt: glyphs only")
        check(SearchToolbarLayout.showsLabels(width: 240, labelled: 93, right: 80), "and then they fit")
        check(SearchToolbarLayout.resultsBottom == 55, "results scroll clear of the capsules")
    }))

    // No two controls in the window's strips ever overlap: the hover bars, the traffic lights, Search's capsules
    // and field, the find shelf — in every mode, at the minimum, default and very wide sizes.
    SelfTest.cases.append(("ShellKit.chromeNoOverlap", {
        MainActor.assumeIsolated {
            let b = Bench()
            defer { b.cleanup() }
            b.store.setSlot(1, for: b.store.create(content: "# Aphrodite\nSlot two.").id)
            var locked = b.store.create(content: "# Ouranos\nPrivate.")
            locked.isLocked = true
            b.store.update(locked)
            b.store.setSlot(6, for: locked.id)
            _ = b.store.create(content: "an older note")
            _ = b.store.create(content: "the front note, being written")
            WindowPreview.reload()
            let notes = (0..<6).map { Note(content: "note \($0) with a line of text to search", created: Date(), modified: Date()) }
            let tracked: Set<String> = ["ChromeButton", "ToolbarCapsule", "FindShelf", "SlotsBarView"]
            let identified: Set<String> = ["SearchField", "BottomBarInfo"]

            /// Visible controls (name and frame in the frame view): hidden views, hidden bars (alpha 0) and the
            /// view tree below a control are left out.
            @MainActor func controls(in frame: NSView) -> [(name: String, frame: NSRect)] {
                var out: [(String, NSRect)] = []
                func walk(_ v: NSView, alpha: CGFloat) {
                    let a = alpha * v.alphaValue
                    guard !v.isHidden, a > 0.01 else { return }
                    let name = "\(type(of: v))"
                    if tracked.contains(name) || identified.contains(v.identifier?.rawValue ?? "") {
                        out.append((v.identifier?.rawValue ?? name, v.superview!.convert(v.frame, to: frame)))
                        return
                    }
                    v.subviews.forEach { walk($0, alpha: a) }
                }
                walk(frame, alpha: 1)
                let window = WindowPreview.window
                for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                    if let light = window.standardWindowButton(kind), light.alphaValue > 0, let sup = light.superview {
                        out.append(("light", sup.convert(light.frame, to: frame)))
                    }
                }
                return out
            }

            @MainActor func verify(_ label: String, _ frame: NSView, buttons: Int, capsules: Int = 0, shelf: Bool = false) {
                frame.layoutSubtreeIfNeeded()
                let found = controls(in: frame)
                let names = found.map(\.name)
                check(names.filter { $0 == "ChromeButton" }.count == buttons, "\(label): \(buttons) chrome buttons, got \(names)")
                check(names.filter { $0 == "ToolbarCapsule" }.count == capsules, "\(label): \(capsules) capsules")
                check(names.contains("FindShelf") == shelf, "\(label): find shelf \(shelf ? "docked" : "away")")
                check(names.filter { $0 == "light" }.count == 3, "\(label): three traffic lights")
                for (i, a) in found.enumerated() {
                    check(frame.bounds.contains(a.frame), "\(label): \(a.name) \(a.frame) inside the window \(frame.bounds)")
                    for c in found[(i + 1)...] where a.frame.intersects(c.frame) {
                        check(false, "\(label): \(a.name) \(a.frame) overlaps \(c.name) \(c.frame)")
                    }
                }
                // The traffic lights, as measured, sit on the top row's centre line; the top bar's buttons keep two
                // gaps clear of the zoom button, so no hover background comes near a light.
                let lights = found.filter { $0.name == "light" }.sorted { $0.frame.minX < $1.frame.minX }
                let topButtons = found.filter { $0.name == "ChromeButton" && $0.frame.maxY > frame.bounds.height - ChromeMetrics.topBarHeight }
                if let close = lights.first, let zoom = lights.last {
                    check(close.frame.minX == ChromeMetrics.trafficLights.start && zoom.frame.maxX == ChromeMetrics.trafficLights.end,
                          "\(label): ChromeMetrics carries the measured lights \(ChromeMetrics.trafficLights), got \(close.frame.minX)…\(zoom.frame.maxX)")
                    check(abs(close.frame.midY - (frame.bounds.height - ChromeMetrics.row)) < 0.5, "\(label): lights centred on the row")
                    for b in topButtons {
                        check(b.frame.minX - zoom.frame.maxX >= ChromeMetrics.groupGap - 0.5,
                              "\(label): \(b.frame) keeps \(ChromeMetrics.groupGap) pt clear of the zoom button \(zoom.frame)")
                        check(abs(b.frame.midY - close.frame.midY) < 0.5, "\(label): button \(b.frame) centred on the lights' line \(close.frame.midY)")
                    }
                    // New Note and Pin are the right group; whatever is left of them follows the lights.
                    let ordered = topButtons.sorted { $0.frame.minX < $1.frame.minX }
                    let left = Array(ordered.dropLast(2)), right = Array(ordered.suffix(2))
                    check(left.first?.frame.minX == zoom.frame.maxX + ChromeMetrics.groupGap, "\(label): the left group starts two gaps after zoom")
                    for pair in Array(zip(left, left.dropFirst())) + Array(zip(right, right.dropFirst())) {
                        check(abs(pair.1.frame.minX - pair.0.frame.maxX - ChromeMetrics.spacing) < 0.5, "\(label): equal gaps in each group")
                    }
                    check(right.last.map { frame.bounds.width - $0.frame.maxX } == ChromeMetrics.sideInset, "\(label): the right group ends one inset in")
                }
            }

            for width in [240.0, 350.0, 600.0, 1200.0] {
                let size = NSSize(width: width, height: 400)
                let w = "\(Int(width)) pt"
                // The note: five top buttons; Delete, Previous, Next and (room allowing) First, Export below.
                let fit = BottomBarLayout.fit(width: width, textWidth: 120)
                let top = 2 + ChromeMetrics.leftButtonsFitting(width: width, left: 3, right: 2)
                verify("note at \(w)", WindowPreview.frameView(revealed: true, size: size), buttons: top + fit.buttons)
                verify("slot at \(w)", WindowPreview.frameView(revealed: true, slot: 1, size: size), buttons: top + fit.buttons)
                verify("locked at \(w)", WindowPreview.frameView(revealed: true, slot: 6, size: size), buttons: top + fit.buttons)
                WindowPreview.backToNotes()
                verify("slot bar at \(w)", WindowPreview.frameView(revealed: true, size: size, hoveredSlot: 1, slotBar: .hovering),
                       buttons: top + fit.buttons)
                // Search owns the bottom strip: its capsules, no bottom bar.
                for (mode, pane) in [("list", ToolsPreviews.search(notes: notes)), ("cards", ToolsPreviews.search(notes: notes, cards: true)),
                                     ("select", ToolsPreviews.search(notes: notes, selecting: true))] {
                    let frame = WindowPreview.frameView(revealed: true, size: size, presenting: pane)
                    check(frame.bounds.width == width && pane.frame.width == width, "search \(mode) at \(w): the pane fits the window, got \(pane.frame)")
                    verify("search \(mode) at \(w)", frame, buttons: top, capsules: 2)
                }
                // The find shelf likewise.
                _ = WindowPreview.frameView(revealed: true, size: size, presenting: nil)
                WindowPreview.perform(.find)
                verify("find at \(w)", WindowPreview.frameView(revealed: true, size: size), buttons: top, shelf: true)
                func buttons(in view: NSView) -> [NSButton] { (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons) }
                buttons(in: WindowPreview.window.contentView!).first { $0.title == "Done" }?.performClick(nil)
                verify("after find at \(w)", WindowPreview.frameView(revealed: true, size: size), buttons: top + fit.buttons)
            }
            WindowPreview.backToNotes()
            _ = WindowPreview.frameView(revealed: false, size: nil, slotBar: .hidden)
        }
    }))
}
