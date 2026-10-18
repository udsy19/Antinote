import AppKit
import SuperNotesCore

/// What the text view draws on top of / behind the text. Rebuilt by `SuperNotesEditor` after each restyle.
struct RenderModel {
    enum Marker: Equatable { case checkbox(checked: Bool), bullet, number(String) }
    /// Hidden, zero-width marker characters (the caret never stops inside them), drawn in the left gutter.
    var markers: [(range: NSRange, kind: Marker, line: Int)] = []
    /// Results drawn right after their line's text; `wraps` puts one on a reserved row below the line.
    var annotations: [(line: NSRange, text: String, wraps: Bool, annotation: LineAnnotation)] = []
    /// The generated summary line ("Total: $40") drawn after a blank line below the note, in `color`.
    var summary: (text: String, color: String)?
    /// Fenced blocks (one rounded rect across their lines) and inline `code` spans.
    var codeBlocks: [NSRange] = []
    var inlineCode: [NSRange] = []
    var theme: Theme = .defaultLight
    var paper: PaperType = .blank
    var paperOpacity: PaperOpacity = .subtle
    var lineHeight: CGFloat = 22
    /// Baseline distance from the top of a line fragment.
    var baselineOffset: CGFloat = 17
    var font: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular)
    var textSize: TextSize = .m
    var doubleSize = false
    var rightToLeft = false
    var blockCaret = false
    /// AutoPaste is listening: a blinking clipboard sits in the gutter at the first line.
    var autoPasting = false
    /// Points the caret is raised (Settings → Editor → Caret height offset).
    var caretNudge: CGFloat = 0
}

/// Note geometry for a size preset. The text starts after a fixed gutter (32 pt, wider with "Double font size"),
/// the 8 pt stack spacing and the 5 pt line padding; list markers are centred at a per-size x in that gutter.
public enum Gutter {
    /// The text box sits this far below the top of the window.
    public static let top: CGFloat = 30

    /// Distance from the window edge to the text.
    public static func inset(_ size: TextSize, double: Bool) -> CGFloat {
        (double ? [42, 42, 42, 45, 52][size.index] : 32) + 8 + 5
    }

    /// Horizontal centre of a list marker (checkbox, bullet, number), from the window edge.
    public static func markerCenter(_ size: TextSize, double: Bool) -> CGFloat {
        (double ? [34, 30, 30, 30, 32] : [34, 30, 28, 23, 23])[size.index]
    }

    /// Bullets are a filled circle symbol at 40% of the text size.
    public static func bulletPointSize(_ fontSize: CGFloat) -> CGFloat { fontSize * 0.4 }

    /// Numbers are right-aligned in a box 1.05 × the text size wide, centred on the marker centre.
    public static func numberBoxWidth(_ fontSize: CGFloat) -> CGFloat { fontSize * 1.05 }

    /// List notes: tighter lines with paragraph spacing on blank paper; regular lines that follow ruled or
    /// gridded paper otherwise.
    public static func listLineMultiple(paper: PaperType) -> CGFloat { paper == .blank ? 1.2 : 1.4 }
    public static func listParagraphSpacing(_ size: TextSize, paper: PaperType) -> CGFloat {
        paper == .blank ? [7, 7.5, 9, 12, 16][size.index] : 0
    }

    /// Paper lines run this far below each text baseline.
    public static func paperBaselineOffset(_ size: TextSize) -> CGFloat { [-0.24, 0.53, 1, 1.07, 1.15][size.index] }
}

public extension TextSize {
    /// Position in the XS…XL ladder.
    var index: Int { Self.allCases.firstIndex(of: self) ?? 2 }
}

/// The note's NSTextView (TextKit 1). Keyboard, clipboard, mouse and drag events go to `SuperNotesEditor` first;
/// drawing adds paper, code backgrounds, gutter markers, inline results and the summary line.
final class EditorTextView: NSTextView {
    weak var editor: SuperNotesEditor?
    var model = RenderModel() {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            if (oldValue.summary == nil) != (model.summary == nil) { sizeToFit() }
            setAutoPasteBlink(model.autoPasting)
        }
    }
    private(set) var annotationHits: [(rect: NSRect, annotation: LineAnnotation, line: NSRange)] = []
    private var hoveredMarker: Int? { didSet { if hoveredMarker != oldValue { needsDisplay = true } } }
    private var blinkTimer: Timer?
    private var hoverArea: NSTrackingArea?
    private var autoPasteGlyphOn = true
    var isDropTargeted = false { didSet { editor?.setDropOverlay(visible: isDropTargeted) } }

    // MARK: Geometry

    func rect(for range: NSRange) -> NSRect {
        guard let lm = layoutManager, let tc = textContainer else { return .zero }
        let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return lm.boundingRect(forGlyphRange: glyphs, in: tc).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    /// Glyph origin of the character at `index` in view coordinates: x where it starts, y its baseline.
    func glyphPoint(at index: Int) -> NSPoint {
        let length = (string as NSString).length
        guard let lm = layoutManager, length > 0 else {
            return NSPoint(x: textContainerOrigin.x, y: textContainerOrigin.y + model.baselineOffset)
        }
        if index >= length, lm.extraLineFragmentRect != .zero {
            let extra = lm.extraLineFragmentRect
            return NSPoint(x: extra.minX + textContainerOrigin.x, y: extra.minY + model.baselineOffset + textContainerOrigin.y)
        }
        let glyph = lm.glyphIndexForCharacter(at: min(index, length - 1))
        let frag = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let loc = lm.location(forGlyphAt: glyph)
        return NSPoint(x: frag.minX + loc.x + textContainerOrigin.x, y: frag.minY + loc.y + textContainerOrigin.y)
    }

    /// Where the text of `line` ends (x) and the baseline of its last fragment; an empty line reports its start.
    func lineEnd(_ line: NSRange) -> NSPoint {
        guard let lm = layoutManager, let tc = textContainer, line.length > 0 else { return glyphPoint(at: line.location) }
        let glyph = lm.glyphIndexForCharacter(at: NSMaxRange(line) - 1)
        let frag = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let box = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc)
        let x = model.rightToLeft ? box.minX : box.maxX
        return NSPoint(x: x + textContainerOrigin.x, y: frag.minY + lm.location(forGlyphAt: glyph).y + textContainerOrigin.y)
    }

    /// The gutter box of marker `i`: a text-sized square centred on the marker column and the first line's
    /// capitals (bullets and numbers centre on it too).
    func checkboxRect(_ i: Int) -> NSRect {
        let p = glyphPoint(at: model.markers[i].range.location)
        let side = model.font.pointSize
        let indent = p.x - textContainerOrigin.x
        let midX = Gutter.markerCenter(model.textSize, double: model.doubleSize) + indent
        let midY = p.y - model.font.capHeight / 2
        return NSRect(x: midX - side / 2, y: midY - side / 2, width: side, height: side)
    }

    var textEdges: (start: CGFloat, end: CGFloat) {
        (textContainerOrigin.x, bounds.width - textContainerOrigin.x)
    }

    /// Keeps the view at least as tall as the visible area (above any chrome resting over the bottom of the note)
    /// so the paper fills it, plus room for the summary.
    override func setFrameSize(_ newSize: NSSize) {
        var size = newSize
        if model.summary != nil { size.height += model.lineHeight * 2 }
        if let clip = enclosingScrollView?.contentView {
            size.height = max(size.height, clip.bounds.height - clip.contentInsets.top - clip.contentInsets.bottom)
        }
        super.setFrameSize(size)
    }

    // MARK: Drawing

    override func drawBackground(in dirty: NSRect) {
        let theme = model.theme
        NSColor(hex: theme.background).setFill()
        dirty.fill()
        drawPaper(in: dirty)
        NSColor(hex: theme.backgroundFade).setFill()
        for block in model.codeBlocks {
            let r = EditorLogic.codeBlockRect(lines: lineFragments(for: block))
            guard r.intersects(dirty) else { continue }
            NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill()
        }
        for span in model.inlineCode {
            let r = EditorLogic.inlineCodeRect(glyphs: rect(for: span))
            guard r.intersects(dirty) else { continue }
            NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill()
        }
    }

    /// The union of the line fragments (full container width) holding `range`, in view coordinates.
    private func lineFragments(for range: NSRange) -> NSRect {
        guard let lm = layoutManager else { return .zero }
        let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var union = NSRect.null
        lm.enumerateLineFragments(forGlyphRange: glyphs) { frag, _, _, _, _ in union = union.union(frag) }
        return union.isNull ? .zero : union.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    /// Paper follows the text: ruled lines and dot rows run just under each baseline at the line pitch; the
    /// large grid uses the line pitch and the small grid half of it, from the window's left edge.
    private func drawPaper(in rect: NSRect) {
        guard model.paper != .blank, model.lineHeight > 4 else { return }
        NSColor(hex: model.theme.grid(model.paperOpacity)).setFill()
        let hairline = 1 / max(window?.backingScaleFactor ?? 2, 1)
        let pitch = model.paper == .smallGrid ? model.lineHeight / 2 : model.lineHeight
        let phase = textContainerOrigin.y + model.baselineOffset + Gutter.paperBaselineOffset(model.textSize)
        var y = phase + ((rect.minY - phase) / pitch).rounded(.down) * pitch
        while y <= rect.maxY + pitch {
            switch model.paper {
            case .blank: break
            case .lines, .smallGrid, .bigGrid:
                NSRect(x: rect.minX, y: y, width: rect.width, height: hairline).fill()
            case .dots:
                let d: CGFloat = 1.5
                var x = (rect.minX / pitch).rounded(.down) * pitch
                while x <= rect.maxX + pitch {
                    NSBezierPath(ovalIn: NSRect(x: x - d / 2, y: y - d / 2, width: d, height: d)).fill()
                    x += pitch
                }
            }
            y += pitch
        }
        guard model.paper == .smallGrid || model.paper == .bigGrid else { return }
        var x = (rect.minX / pitch).rounded(.down) * pitch
        while x <= rect.maxX { NSRect(x: x, y: rect.minY, width: hairline, height: rect.height).fill(); x += pitch }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // NSTextView leaves the clip at the text container; the gutter and results draw outside it.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: dirtyRect).setClip()
        drawMarkers(dirtyRect)
        drawAnnotations(dirtyRect)
        drawSummary()
        drawAutoPasteGlyph()
    }

    /// Checkboxes are the `square` / `checkmark.square` symbols at the text size: `typeMain`, `accent2Secondary`
    /// once checked, `accent2Main` (unchecked) or `typeMain` (checked) under the pointer. Bullets are a small
    /// `circle.fill`; numbers are right-aligned text in a box around the marker column.
    private func drawMarkers(_ dirtyRect: NSRect) {
        let theme = model.theme, font = model.font
        for (i, m) in model.markers.enumerated() {
            let box = checkboxRect(i)
            guard box.insetBy(dx: -40, dy: -4).intersects(dirtyRect) else { continue }
            switch m.kind {
            case .checkbox(let checked):
                let hovered = hoveredMarker == i
                let color = checked ? (hovered ? theme.typeMain : theme.accent2Secondary) : (hovered ? theme.accent2Main : theme.typeMain)
                drawSymbol(checked ? "checkmark.square" : "square", pointSize: font.pointSize, color: NSColor(hex: color),
                           centeredIn: box)
            case .bullet:
                drawSymbol("circle.fill", pointSize: Gutter.bulletPointSize(font.pointSize), color: NSColor(hex: theme.typeMain),
                           centeredIn: box)
            case .number(let label):
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(hex: theme.typeMain)]
                let width = (label as NSString).size(withAttributes: attrs).width
                let right = box.midX + Gutter.numberBoxWidth(font.pointSize) / 2
                let p = glyphPoint(at: m.range.location)
                (label as NSString).draw(at: NSPoint(x: right - width, y: p.y - font.ascender), withAttributes: attrs)
            }
        }
    }

    private func drawSymbol(_ name: String, pointSize: CGFloat, color: NSColor, centeredIn box: NSRect) {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(.init(paletteColors: [color]))
        let image = symbol.withSymbolConfiguration(config) ?? symbol
        let size = image.size
        image.draw(in: NSRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func drawAnnotations(_ dirtyRect: NSRect) {
        annotationHits.removeAll()
        let theme = model.theme, font = model.font
        let (start, end) = textEdges
        for a in model.annotations {
            let color: NSColor
            switch a.annotation.kind {
            case .result: color = NSColor(hex: theme.accent3Main)
            case .error: color = NSColor(hex: theme.accent5Main)
            case .info: color = NSColor(hex: theme.typeLight)
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let endPoint = lineEnd(a.line)
            let text = a.wraps ? a.annotation.text : a.text
            let width = (text as NSString).size(withAttributes: attrs).width
            let place = EditorLogic.Annotations.place(lineEnd: endPoint.x, width: width, textStart: start, textEnd: end,
                                                      rightToLeft: model.rightToLeft)
            let baseline = endPoint.y + (a.wraps ? model.lineHeight : 0)
            let x = a.wraps ? (model.rightToLeft ? end - width : start) : place.x
            let r = NSRect(x: x, y: baseline - font.ascender, width: width, height: font.ascender - font.descender)
            annotationHits.append((r.insetBy(dx: -4, dy: -2), a.annotation, a.line))
            guard r.intersects(dirtyRect) else { continue }
            (text as NSString).draw(at: r.origin, withAttributes: attrs)
        }
    }

    private func drawSummary() {
        guard let summary = model.summary else { return }
        let s = string as NSString
        var baseline: CGFloat
        if s.length == 0 || s.hasSuffix("\n") {
            baseline = glyphPoint(at: s.length).y
        } else {
            let last = s.lineRange(for: NSRange(location: s.length - 1, length: 0))
            baseline = lineEnd(last).y
            if model.annotations.contains(where: { NSMaxRange($0.line) == s.length && $0.wraps }) { baseline += model.lineHeight }
        }
        baseline += model.lineHeight * 2
        let font = model.font
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(hex: summary.color)]
        (summary.text as NSString).draw(at: NSPoint(x: textEdges.start, y: baseline - font.ascender), withAttributes: attrs)
    }

    private var autoPasteGlyphRect: NSRect {
        let side = model.font.pointSize + 2
        let baseline = textContainerOrigin.y + model.baselineOffset
        return NSRect(x: Gutter.markerCenter(model.textSize, double: model.doubleSize) - side / 2,
                      y: baseline - model.font.capHeight / 2 - side / 2, width: side, height: side)
    }

    private func drawAutoPasteGlyph() {
        guard model.autoPasting,
              let symbol = NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: "AutoPaste") else { return }
        let config = NSImage.SymbolConfiguration(pointSize: model.font.pointSize * 0.85, weight: .regular)
            .applying(.init(paletteColors: [NSColor(hex: model.theme.accent3Main)]))
        let image = symbol.withSymbolConfiguration(config) ?? symbol
        let r = autoPasteGlyphRect, size = image.size
        image.draw(in: NSRect(x: r.midX - size.width / 2, y: r.midY - size.height / 2, width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: autoPasteGlyphOn ? 1 : 0.3, respectFlipped: true, hints: nil)
    }

    /// Blinks the AutoPaste glyph (1 s period, opacity 1 ↔ 0.3) while listening.
    private func setAutoPasteBlink(_ on: Bool) {
        guard on != (blinkTimer != nil) else { return }
        blinkTimer?.invalidate()
        blinkTimer = nil
        autoPasteGlyphOn = true
        guard on else { return }
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.autoPasteGlyphOn.toggle()
                self.setNeedsDisplay(self.autoPasteGlyphRect.insetBy(dx: -2, dy: -2))
            }
        }
    }

    // MARK: Caret

    /// A 2 pt rounded caret, cap height + 7.8 pt tall, standing on the bottom of the line; a block in Vim normal mode.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        let font = (typingAttributes[.font] as? NSFont) ?? model.font
        if model.blockCaret {
            var r = rect
            r.size.width = max(("m" as NSString).size(withAttributes: [.font: font]).width, 2)
            if flag { color.withAlphaComponent(0.45).setFill(); r.fill() } else { setNeedsDisplay(r, avoidAdditionalLayout: true) }
            return
        }
        guard flag else { return setNeedsDisplay(rect.insetBy(dx: 0, dy: -abs(model.caretNudge)), avoidAdditionalLayout: true) }
        let caret = EditorLogic.caretRect(lineRect: rect, capHeight: font.capHeight, leading: font.leading, nudge: model.caretNudge)
        color.setFill()
        NSBezierPath(roundedRect: caret, xRadius: 1, yRadius: 1).fill()
    }

    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        var r = rect
        r.size.width += model.blockCaret ? model.lineHeight : 2
        super.setNeedsDisplay(r, avoidAdditionalLayout: flag)
    }

    // MARK: Cursor & hover

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isEditable else { return }
        for (i, m) in model.markers.enumerated() {
            if case .checkbox = m.kind { addCursorRect(checkboxRect(i).insetBy(dx: -3, dy: -3), cursor: .pointingHand) }
        }
        for hit in annotationHits { addCursorRect(hit.rect, cursor: .pointingHand) }
    }

    /// The checkbox marker under `p`, if any.
    func checkbox(at p: NSPoint) -> Int? {
        model.markers.indices.first { i in
            if case .checkbox = model.markers[i].kind { return checkboxRect(i).insetBy(dx: -3, dy: -3).contains(p) }
            return false
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let p = convert(event.locationInWindow, from: nil)
        hoveredMarker = isEditable ? checkbox(at: p) : nil
        editor?.hover(at: p)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoveredMarker = nil
        editor?.hover(at: nil)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        editor?.applyAppearance()
    }

    // MARK: Events

    /// Undo belongs to the editor (`NoteHistory`), not the text view: with no manager of its own, NSTextView
    /// registers nothing, and Edit › Undo / Redo (nil-targeted, so they land on the first responder) run the
    /// note's history or the shell's note-level step.
    override var undoManager: UndoManager? { nil }

    @objc func undo(_ sender: Any?) { editor?.activeUndoManager.undo() }
    @objc func redo(_ sender: Any?) { editor?.activeUndoManager.redo() }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if editor?.handleClick(at: p, event: event) == true { return }
        super.mouseDown(with: event)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        if ranges.count == 1, let clamped = editor?.clampedCaret(from: selectedRange(), to: ranges[0].rangeValue) {
            return super.setSelectedRanges([NSValue(range: clamped)], affinity: affinity, stillSelecting: stillSelecting)
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
    }

    override func keyDown(with event: NSEvent) {
        if editor?.handleKeyDown(event) == true { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, editor?.handleKeyEquivalent(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        if editor?.handleReturn() == true { return }
        super.insertNewline(sender)
    }

    override func insertTab(_ sender: Any?) {
        if editor?.handleTab(backwards: false) == true { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if editor?.handleTab(backwards: true) == true { return }
        super.insertBacktab(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        if editor?.handleDeleteBackward() == true { return }
        super.deleteBackward(sender)
    }

    /// Esc is handled in `keyDown`; never open the system completion list.
    override func cancelOperation(_ sender: Any?) {}

    override func copy(_ sender: Any?) { editor?.copySelection(cut: false) }
    override func cut(_ sender: Any?) { editor?.copySelection(cut: true) }
    override func paste(_ sender: Any?) { editor?.paste(from: .general) }
    override func pasteAsPlainText(_ sender: Any?) { editor?.paste(from: .general) }
    override func pasteAsRichText(_ sender: Any?) { editor?.paste(from: .general) }

    /// Copy/cut work without a selection (whole note / current line); Undo and Redo show what they would do
    /// ("Undo Typing", "Redo Paste").
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) { return true }
        if item.action == #selector(cut(_:)) { return isEditable }
        if item.action == #selector(undo(_:)) || item.action == #selector(redo(_:)) {
            guard let manager = editor?.activeUndoManager else { return false }
            let undoing = item.action == #selector(undo(_:))
            (item as? NSMenuItem)?.title = undoing ? manager.undoMenuItemTitle : manager.redoMenuItemTitle
            return undoing ? manager.canUndo : manager.canRedo
        }
        return super.validateUserInterfaceItem(item)
    }

    // MARK: Drag & drop (images → OCR)

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + [.fileURL, .png, .tiff]
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if OCR.hasImage(sender.draggingPasteboard), isEditable { isDropTargeted = true; return .copy }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if isDropTargeted { return .copy }
        return super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTargeted = false
        super.draggingExited(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if isDropTargeted {
            isDropTargeted = false
            let p = convert(sender.draggingLocation, from: nil)
            let index = characterIndexForInsertion(at: p)
            setSelectedRange(NSRange(location: index, length: 0))
            editor?.recognizeImage(from: sender.draggingPasteboard)
            return true
        }
        return super.performDragOperation(sender)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        isDropTargeted = false
        super.concludeDragOperation(sender)
    }
}

/// A thin (4 pt) rounded scroll knob in `typeHighlight` near the right edge, at least 50 pt long, with no track.
final class ThinScroller: NSScroller {
    var knobColor: NSColor = .tertiaryLabelColor { didSet { needsDisplay = true } }

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let knob = rect(for: .knob), slot = rect(for: .knobSlot)
        guard knob.height > 0 else { return }
        var r = NSRect(x: knob.maxX - 7, y: knob.minY + 3, width: 4, height: knob.height - 6)
        if r.height < 50 {
            // Grow a short knob to 50 pt, keeping it inside the slot.
            r.origin.y = min(max(slot.minY, r.midY - 25), slot.maxY - 50)
            r.size.height = min(50, slot.height)
        }
        knobColor.setFill()
        NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill()
    }
}
