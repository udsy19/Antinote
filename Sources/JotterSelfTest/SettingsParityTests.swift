import Foundation
import JotterCore
import ShellKit

/// Settings layout details that follow the reference app.
func registerSettingsParityTests() {
    SelfTest.cases.append(("ShellKit.keywordGroups", {
        check(KeywordGroups.order == [.list, .math, .sum, .average, .count, .code, .timer, .autopaste],
              "groups run List, Math, Sum, Avg, Count, Code, Timer, then Paste")
        check(KeywordGroups.order.map(KeywordGroups.title) == ["List", "Math", "Sum", "Avg", "Count", "Code", "Timer", "Paste"],
              "short group titles")
        check(!KeywordGroups.order.contains(.plain), "plain text has no keywords")
    }))
}
