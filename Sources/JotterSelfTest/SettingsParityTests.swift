import Foundation
import JotterCore
import ShellKit

/// Settings layout details that follow the reference app.
func registerSettingsParityTests() {
    SelfTest.cases.append(("ShellKit.keywordGroups", {
        check(NoteMode.keywordModes == [.list, .math, .sum, .average, .count, .code, .timer, .autopaste],
              "groups run List, Math, Sum, Avg, Count, Code, Timer, then Paste")
        check(NoteMode.keywordModes.map(KeywordGroups.title) == ["List", "Math", "Sum", "Avg", "Count", "Code", "Timer", "Paste"],
              "short group titles")
        check(!NoteMode.keywordModes.contains(.plain), "plain text has no keywords")
    }))
}
