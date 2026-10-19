import Foundation
import CoreGraphics

/// One size system for everything that sits in the main window's top or bottom strip: the hover bars' buttons,
/// Search's toolbar capsules, and any mode's own controls. A button is a 30 pt square with a 22 pt glyph; a row
/// of them is centred 20 pt from the window edge (the traffic lights are moved onto the same row), its first
/// button 10 pt in from the side, with 8 pt between neighbours. Hover and pressed backgrounds are 5 pt rounded
/// squares. The top bar's left group follows the traffic lights as the system really places them (macOS 26 spaces
/// them wider than 14 and 15 do): it starts two gaps (16 pt) after the zoom button, so the lights and the glyphs
/// read as two groups — the glyph is then 20 pt from the zoom button, more than the 16 pt between glyphs.
///
/// A mode that brings its own bottom controls (Search's capsules, the editor's find shelf) takes the bottom strip
/// over: the window's bottom bar stays down while they show, so no two controls ever overlap.
public enum ChromeMetrics {
    /// A button's hit square.
    public static let button: CGFloat = 30
    /// The glyph drawn inside it (4 pt inset on every side).
    public static let glyph: CGFloat = 22
    /// Hover / pressed background corner radius.
    public static let cornerRadius: CGFloat = 5
    /// From the window's side to the first or last button.
    public static let sideInset: CGFloat = 10
    /// Between neighbouring buttons.
    public static let spacing: CGFloat = 8
    /// Between the zoom button and the top bar's left group: two button gaps.
    public static let groupGap: CGFloat = 2 * spacing
    /// Centre of the button row, measured from the window's top edge (top bar) or bottom edge (bottom bar).
    public static let row: CGFloat = 20
    /// The hover strips: the top bar covers its row and 5 pt below it, the bottom bar its row and the same above.
    public static let topBarHeight: CGFloat = 35
    public static let bottomBarHeight: CGFloat = 40

    /// The traffic lights' horizontal extent, from the window's left edge: where the close button starts and the
    /// zoom button ends. The main window measures its real buttons (`MainWindow.measureTrafficLights`); until then
    /// the values are macOS 14 and 15's (close at 7, 14 pt wide, 20 pt pitch; macOS 26 has 9 and 23).
    public struct TrafficLights: Equatable {
        public var start: CGFloat
        public var end: CGFloat
        public init(start: CGFloat, end: CGFloat) {
            self.start = start
            self.end = end
        }
    }
    public static var trafficLights = TrafficLights(start: 7, end: 61)

    /// Where the top bar's left group starts: two gaps after the zoom button.
    public static var leadingInset: CGFloat { trafficLights.end + groupGap }

    /// How many of the top bar's `left` buttons fit beside its `right` ones in a window `width` wide, one gap
    /// between the groups: the left group loses its last button first (Typing), never going below `keep`.
    public static func leftButtonsFitting(width: CGFloat, left: Int, right: Int, keep: Int = 2) -> Int {
        var n = left
        while n > keep, topBarWidth(left: n, right: right) > width { n -= 1 }
        return n
    }

    /// The width the top bar needs for `left` buttons after the traffic lights and `right` buttons at the far
    /// side, one gap between the groups.
    public static func topBarWidth(left: Int, right: Int) -> CGFloat {
        leadingInset + CGFloat(left) * button + CGFloat(max(left - 1, 0)) * spacing + spacing
            + CGFloat(right) * button + CGFloat(max(right - 1, 0)) * spacing + sideInset
    }

    /// Frames of `count` buttons laid left to right from `x`.
    public static func buttons(_ count: Int, from x: CGFloat, y: CGFloat) -> [CGRect] {
        (0..<count).map { CGRect(x: x + CGFloat($0) * (button + spacing), y: y, width: button, height: button) }
    }
}
