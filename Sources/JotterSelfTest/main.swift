import Foundation
import JotterCore

// Headless logic checks (the Command Line Tools have no XCTest). Run: swift run JotterSelfTest
var failures = 0
func check(_ cond: @autoclosure () -> Bool, _ msg: String, file: String = #fileID, line: Int = #line) {
    if !cond() { failures += 1; print("✗ \(file):\(line) \(msg)") }
}
enum SelfTest { nonisolated(unsafe) static var cases: [(String, () -> Void)] = [] }

SelfTest.cases.append(("Core.modeDetection", {
    check(NoteMode.detect(firstLine: "Math").mode == .math, "case-insensitive keyword")
    let t = NoteMode.detect(firstLine: "timer 25m")
    check(t.mode == .timer && t.arguments == "25m", "keyword with arguments")
    check(NoteMode.detect(firstLine: "mathematics is fun").mode == .plain, "whole-word keywords only")
    let titled = NoteMode.detect(firstLine: "list: Groceries")
    check(titled.mode == .list && titled.arguments == "Groceries", "keyword with a colon title")
    check(NoteMode.detect(firstLine: "timer 5:30").arguments == "5:30", "clock times keep their colon")
}))

registerModuleTests()
for (name, run) in SelfTest.cases {
    let before = failures; run()
    print(failures == before ? "✓ \(name)" : "✗ \(name)")
}
print(failures == 0 ? "All self-tests passed." : "\(failures) failure(s).")
exit(failures == 0 ? 0 : 1)
