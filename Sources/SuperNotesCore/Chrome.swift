import Foundation
import CoreGraphics

/// One size system for everything that sits in the main window's top or bottom strip: the hover bars' buttons,
/// Search's toolbar capsules, and any mode's own controls. A button is a 30 pt square with a 22 pt glyph; a row
/// of them is centred 20 pt from the window edge (the traffic lights are moved onto the same row), its first
/// button 10 pt in from the side (the top bar's left group follows the traffic lights, one gap after the zoom
/// button), with 8 pt between neighbours. Hover and pressed backgrounds are 5 pt rounded squares.
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
    /// Centre of the button row, measured from the window's top edge (top bar) or bottom edge (bottom bar).
    public static let row: CGFloat = 20
    /// Where the traffic lights end: the zoom button's right edge (close at x 7, 14 pt wide, 20 pt pitch).
    public static let trafficLightsEnd: CGFloat = 61
    /// Where the top bar's left group starts: one gap after the traffic lights.
    public static var leadingInset: CGFloat { trafficLightsEnd + spacing }
    /// The hover strips: the top bar covers its row and 5 pt below it, the bottom bar its row and the same above.
    public static let topBarHeight: CGFloat = 35
    public static let bottomBarHeight: CGFloat = 40

    /// How many of the top bar's `left` buttons fit beside its `right` ones in a window `width` wide, one gap
    /// between the groups: the left group loses its last button first (Typing), never going below `keep`.
    public static func leftButtonsFitting(width: CGFloat, left: Int, right: Int, keep: Int = 2) -> Int {
        func needed(_ n: Int) -> CGFloat {
            leadingInset + CGFloat(n) * button + CGFloat(n - 1) * spacing + spacing
                + CGFloat(right) * button + CGFloat(max(right - 1, 0)) * spacing + sideInset
        }
        var n = left
        while n > keep, needed(n) > width { n -= 1 }
        return n
    }

    /// Frames of `count` buttons laid left to right from `x`.
    public static func buttons(_ count: Int, from x: CGFloat, y: CGFloat) -> [CGRect] {
        (0..<count).map { CGRect(x: x + CGFloat($0) * (button + spacing), y: y, width: button, height: button) }
    }
}
