import AppKit
import SuperNotesCore

// Headless logic checks (the Command Line Tools have no XCTest). Run: swift run SuperNotesSelfTest
var failures = 0
func check(_ cond: @autoclosure () -> Bool, _ msg: String, file: String = #fileID, line: Int = #line) {
    if !cond() { failures += 1; print("✗ \(file):\(line) \(msg)") }
}
enum SelfTest { nonisolated(unsafe) static var cases: [(String, () -> Void)] = [] }

// Custom themes, the rates cache and user extensions resolve inside a throwaway folder, never the real one.
SuperNotesPaths.base = FileManager.default.temporaryDirectory.appendingPathComponent("supernotes-selftest-\(UUID().uuidString)")

SelfTest.cases.append(("Core.modeDetection", {
    check(NoteMode.detect(firstLine: "Math").mode == .math, "case-insensitive keyword")
    let t = NoteMode.detect(firstLine: "timer 25m")
    check(t.mode == .timer && t.arguments == "25m", "keyword with arguments")
    check(NoteMode.detect(firstLine: "mathematics is fun").mode == .plain, "whole-word keywords only")
    let titled = NoteMode.detect(firstLine: "list: Groceries")
    check(titled.mode == .list && titled.arguments == "Groceries", "keyword with a colon title")
    check(NoteMode.detect(firstLine: "timer 5:30").arguments == "5:30", "clock times keep their colon")
}))

SelfTest.cases.append(("Core.themeTable", {
    let names = Theme.builtIn.map(\.name)
    check(names == ["Default Light", "Default Dark", "Mecha", "Masquerade", "Meadow", "Cedar", "Arthouse", "Dune", "Armor",
                    "Stealth", "Fern", "Highland", "Spice", "Bubblegum"], "built-in theme names and order")
    check(Set(Theme.builtIn.map(\.id)).count == Theme.builtIn.count, "theme ids are unique")
    check(Theme.defaultLight.typeMain == "#473F37" && Theme.defaultDark.background == "#2A2626", "default pair values")
    check(Theme.builtIn.first { $0.name == "Fern" }?.background == "#F5FFF5", "named theme values")
    check(Theme.builtIn.filter(\.isDark).map(\.name) == ["Default Dark", "Masquerade", "Cedar", "Arthouse", "Dune", "Armor",
                                                         "Stealth"], "dark themes")
    // The five themes added last carry the reference's colours exactly (alpha as #RRGGBBAA).
    func theme(_ name: String) -> Theme? { Theme.builtIn.first { $0.name == name } }
    check(theme("Meadow")?.background == "#FAF5EB" && theme("Meadow")?.accent1Main == "#557D69"
          && theme("Meadow")?.gridBold == "#AAAAA599", "Meadow values")
    check(theme("Armor")?.background == "#0A0A0F" && theme("Armor")?.accent1Secondary == "#3C5082B2"
          && theme("Armor")?.typeReverse == "#000000", "Armor values")
    check(theme("Stealth")?.typeMain == "#CADEE8" && theme("Stealth")?.accent5Secondary == "#F2F6F7CC", "Stealth values")
    check(theme("Spice")?.background == "#E1D2B4" && theme("Spice")?.accent2Main == "#2E92E5", "Spice values")
    check(theme("Bubblegum")?.typeMain == "#E876B2" && theme("Bubblegum")?.accent2Secondary == "#69A76980",
          "Bubblegum values")
    let half = NSColor(hex: Theme.defaultLight.accent2Secondary)
    check(abs(half.alphaComponent - 128.0 / 255) < 0.001 && abs(half.redComponent - 0xC1 / 255.0) < 0.001, "#RRGGBBAA alpha")
    check(NSColor(hex: "#0B486B").alphaComponent == 1, "#RRGGBB is opaque")
}))

registerModuleTests()
for (name, run) in SelfTest.cases {
    let before = failures; run()
    print(failures == before ? "✓ \(name)" : "✗ \(name)")
}
try? FileManager.default.removeItem(at: SuperNotesPaths.base)
print(failures == 0 ? "All self-tests passed." : "\(failures) failure(s).")
exit(failures == 0 ? 0 : 1)
