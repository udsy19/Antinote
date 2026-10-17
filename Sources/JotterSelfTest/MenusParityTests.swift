import AppKit
import JotterCore
import ShellKit

func registerMenusParityTests() {
    SelfTest.cases.append(("ShellKit.exportMenuRows", {
        typealias Row = MenuLogic.ExportRow
        check(MenuLogic.exportRows(enabled: [.appleNotes, .markdown, .plainText, .pdf], quick: nil) == [
            .destination("Plain Text (.txt)", .plainText), .destination("Markdown (.md)", .markdown),
            .destination("PDF (.pdf)", .pdf), .separator, .destination("Send to Apple Notes", .appleNotes),
        ], "files first, then a separator, then the apps")
        check(MenuLogic.exportRows(enabled: [.bear, .obsidian], quick: .markdown) == [
            .quickExport("Quick Export (Markdown)"), .separator,
            .destination("Send to Bear", .bear), .destination("Send to Obsidian", .obsidian),
        ], "Quick Export leads, named without the file extension")
        check(MenuLogic.exportRows(enabled: [.pdf], quick: .plainText).first == Row.quickExport("Quick Export (Plain Text)"),
              "plain text quick export")
        check(MenuLogic.exportRows(enabled: [], quick: nil).isEmpty, "nothing enabled, nothing listed")
        check(MenuLogic.exportRows(enabled: [], quick: .pdf) == [.quickExport("Quick Export (PDF)")], "no trailing separator")
    }))

    SelfTest.cases.append(("ShellKit.menuKeyDisplay", {
        check(MenuLogic.display("1", [.command, .shift]) == "⇧⌘1", "modifiers in menu order")
        check(MenuLogic.display(MenuLogic.upArrow, [.option, .shift]) == "⌥⇧↑", "arrow keys")
        check(MenuLogic.display(" ", .control) == "⌃Space", "space")
        check(MenuLogic.display("k", [.command, .shift]) == "⇧⌘K", "letters upper-cased")
    }))

    SelfTest.cases.append(("ShellKit.menuToggleTitles", {
        check(MenuLogic.Toggle.pin.titles == ("Pin Jotter to Top", "Unpin from Top"), "pin")
        check(MenuLogic.Toggle.readOnly.titles == ("Make Read-Only", "Allow Editing"), "read-only")
        check(MenuLogic.Toggle.allCases.allSatisfy { $0.titles.off != $0.titles.on }, "every toggle changes its title")
    }))
}
