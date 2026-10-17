import AppKit
import JotterCore
import EditorKit

// Editor geometry and styling measured from the reference app (see docs/specs/ui-parity.md).
private func near(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) < 0.001 && abs(a.minY - b.minY) < 0.001 && abs(a.width - b.width) < 0.001 && abs(a.height - b.height) < 0.001
}

func registerEditorParityTests() {
    SelfTest.cases.append(("EditorParity.typography", {
        check(TextSize.allCases.map(\.points) == [10, 12, 14, 16, 18], "size ladder XS…XL is 10/12/14/16/18 pt")
        check(Typography.lineHeight(natural: 16.29, multiple: 1.4) == 16 * 1.4, "line pitch rounds the natural height, then ×1.4")
        check(Typography.lineHeight(natural: 13.5, multiple: 1.2) == 14 * 1.2, "list lines on blank paper use ×1.2")
    }))
    SelfTest.cases.append(("EditorParity.gutter", {
        check(TextSize.allCases.map { Gutter.inset($0, double: false) } == [45, 45, 45, 45, 45], "text starts 45 pt in at every size")
        check(TextSize.allCases.map { Gutter.inset($0, double: true) } == [55, 55, 55, 58, 65], "double size widens the gutter")
        check(TextSize.allCases.map { Gutter.markerCenter($0, double: false) } == [34, 30, 28, 23, 23], "marker centres per size")
        check(Gutter.listLineMultiple(paper: .blank) == 1.2 && Gutter.listLineMultiple(paper: .lines) == 1.4, "list line multiple")
        check(TextSize.allCases.map { Gutter.listParagraphSpacing($0, paper: .blank) } == [7, 7.5, 9, 12, 16], "list item spacing")
        check(Gutter.listParagraphSpacing(.m, paper: .dots) == 0, "no item spacing on non-blank paper")
        check(abs(Gutter.bulletPointSize(14) - 5.6) < 0.001 && abs(Gutter.numberBoxWidth(14) - 14.7) < 0.001, "bullet and number box sizes")
    }))
    SelfTest.cases.append(("EditorParity.drawingGeometry", {
        let caret = EditorLogic.caretRect(lineRect: CGRect(x: 50, y: 30, width: 1, height: 22.4), capHeight: 10.2, leading: 0)
        check(caret.width == 2 && abs(caret.height - 18) < 0.001 && abs(caret.maxY - 52.4) < 0.001, "caret stands on the line bottom")
        check(near(EditorLogic.codeBlockRect(lines: CGRect(x: 45, y: 100, width: 200, height: 44.8)),
                   CGRect(x: 41, y: 98, width: 208, height: 48.8)), "code blocks grow 4 × 2 pt")
        check(near(EditorLogic.inlineCodeRect(glyphs: CGRect(x: 10, y: 0, width: 40, height: 22.4)),
                   CGRect(x: 8, y: 3.8, width: 44, height: 20.8)), "inline code sits 3 pt low")
        check(EditorLogic.actionBadge("replaceLine").symbol == "arrow.left.arrow.right"
              && EditorLogic.actionBadge("insert").role == \Theme.accent3Main
              && EditorLogic.actionBadge("mystery").role == \Theme.typeLight, "action badges")
        check(PillView.duration(for: "Stopwatch started") == 1 + 0.05 * 17, "pills stay 1 s + 50 ms per character")
    }))
}
