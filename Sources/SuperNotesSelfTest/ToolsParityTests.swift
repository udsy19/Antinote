import Foundation
import SuperNotesCore
import ToolsKit

/// Search pane sizing (text one step below the editor's, paddings and card columns).
func registerToolsParityTests() {
    SelfTest.cases.append(("ToolsKit.searchMetrics", {
        let text = TextSize.allCases.map { SearchMetrics.textSize($0, doubled: false) }
        check(text == [10, 10, 12, 14, 16], "text one step below the editor: \(text)")
        check(SearchMetrics.textSize(.m, doubled: true) == 24, "double font size doubles the text")
        let meta = TextSize.allCases.map { SearchMetrics.metaSize($0, doubled: false) }
        check(meta == [10, 10, 10, 12, 14], "meta two steps below: \(meta)")
        check(TextSize.allCases.map(SearchMetrics.rowPadding) == [8, 10, 12, 14, 16], "row padding grows with size")
        check(SearchMetrics.cardTextSize(doubled: false) == 10 && SearchMetrics.cardTextSize(doubled: true) == 20, "card text")
        check(SearchMetrics.iconSize(doubled: false) == 10 && SearchMetrics.iconSize(doubled: true) == 20, "icon size")
        let narrow = SearchMetrics.cardColumns(width: 305)
        check(narrow.count == 1 && narrow.width == 305, "one column in the default window: \(narrow)")
        let two = SearchMetrics.cardColumns(width: 528)
        check(two.count == 2 && two.width == 258, "two columns once 2 × 230 + 12 fit: \(two)")
        let capped = SearchMetrics.cardColumns(width: 471)
        check(capped.count == 1 && capped.width == 340, "a single column stops at 340 pt: \(capped)")
        check(SearchMetrics.cardColumns(width: 120).count == 1, "never fewer than one column")
    }))
}
