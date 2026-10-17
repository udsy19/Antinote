import AppKit
import JotterCore

/// What the text view draws on top of / behind the text. Rebuilt by `JotterEditor` after each restyle.
struct RenderModel {
    enum Marker { case checkbox(checked: Bool), bullet }
    /// Marker characters to draw over (their own text is transparent), the whole marker including its space
    /// (the caret never stops inside it) and the line they belong to.
    var markers: [(range: NSRange, full: NSRange, kind: Marker, line: Int)] = []
    /// Content ranges of the lines that carry annotations, paired with the annotation.
    var annotations: [(line: NSRange, annotation: LineAnnotation)] = []
    /// Character ranges drawn with a rounded code background.
    var codeBlocks: [NSRange] = []
    var theme: Theme = Theme.builtIn[0]
    var paper: PaperType = .blank
    var paperOpacity: Double = 1
    var lineHeight: CGFloat = 20
    var rightToLeft = false
    var blockCaret = false
}

/// The note's NSTextView (TextKit 1). Keyboard, clipboard, mouse and drag events go to `JotterEditor` first;
/// drawing adds paper, code backgrounds, checkboxes, bullets and inline results.
final class EditorTextView: NSTextView {
    weak var editor: JotterEditor?
    var model = RenderModel() { didSet { needsDisplay = true; window?.invalidateCursorRects(for: self) } }
    private(set) var annotationHits: [(rect: NSRect, annotation: LineAnnotation, line: NSRange)] = []
    var isDropTargeted = false { didSet { editor?.setDropOverlay(visible: isDropTargeted) } }

    // MARK: Geometry

    func rect(for range: NSRange) -> NSRect {
        guard let lm = layoutManager, let tc = textContainer else { return .zero }
        let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return lm.boundingRect(forGlyphRange: glyphs, in: tc).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    /// Baseline (view coordinates) of the line fragment holding the end of `line` — results draw on a wrapped
    /// line's last fragment.
    func baseline(of line: NSRange, font: NSFont) -> CGFloat {
        guard let lm = layoutManager else { return 0 }
        let length = (string as NSString).length
        let origin = textContainerOrigin
        if line.location >= length, line.length == 0 {
            let extra = lm.extraLineFragmentRect
            if extra != .zero || length == 0 {
                let frag = extra == .zero ? NSRect(x: 0, y: 0, width: 0, height: model.lineHeight) : extra
                return frag.maxY + origin.y + font.descender
            }
        }
        let charIndex = line.length > 0 ? NSMaxRange(line) - 1 : min(line.location, length - 1)
        let glyph = lm.glyphIndexForCharacter(at: charIndex)
        let frag = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return frag.minY + lm.location(forGlyphAt: glyph).y + origin.y
    }

    /// Keeps the view at least as tall as the visible area so the paper pattern fills it.
    override func setFrameSize(_ newSize: NSSize) {
        var size = newSize
        if let clip = enclosingScrollView?.contentView { size.height = max(size.height, clip.bounds.height) }
        super.setFrameSize(size)
    }

    // MARK: Drawing

    override func drawBackground(in dirty: NSRect) {
        let theme = model.theme
        NSColor(hex: theme.background).setFill()
        dirty.fill()
        drawPaper(in: dirty)
        let codeFill = NSColor(hex: theme.text).withAlphaComponent(theme.isDark ? 0.07 : 0.05)
        for block in model.codeBlocks {
            var r = rect(for: block)
            r.origin.x = textContainerOrigin.x - 10
            r.size.width = bounds.width - textContainerOrigin.x * 2 + 20
            r = r.insetBy(dx: 0, dy: -6)
            guard r.intersects(dirty) else { continue }
            codeFill.setFill()
            NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
        }
    }

    private func drawPaper(in rect: NSRect) {
        guard model.paper != .blank, model.lineHeight > 4 else { return }
        let color = NSColor(hex: model.theme.paperLines).withAlphaComponent(CGFloat(model.paperOpacity))
        color.setFill()
        let step = model.lineHeight
        let top = textContainerOrigin.y
        let firstRow = max(1, Int(((rect.minY - top) / step).rounded(.down)))
        var y = top + CGFloat(firstRow) * step
        switch model.paper {
        case .blank: break
        case .lined:
            while y <= rect.maxY + step {
                NSRect(x: rect.minX, y: y - 0.5, width: rect.width, height: 1).fill(); y += step
            }
        case .grid:
            while y <= rect.maxY + step {
                NSRect(x: rect.minX, y: y - 0.5, width: rect.width, height: 1).fill(); y += step
            }
            var x = (rect.minX / step).rounded(.down) * step
            while x <= rect.maxX { NSRect(x: x - 0.5, y: rect.minY, width: 1, height: rect.height).fill(); x += step }
        case .dotted:
            while y <= rect.maxY + step {
                var x = (rect.minX / step).rounded(.down) * step
                while x <= rect.maxX {
                    NSBezierPath(ovalIn: NSRect(x: x - 1.25, y: y - 1.25, width: 2.5, height: 2.5)).fill(); x += step
                }
                y += step
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let theme = model.theme
        let accent = NSColor(hex: theme.accent)
        for m in model.markers {
            let r = rect(for: m.range)
            guard r.intersects(dirtyRect) else { continue }
            let font = (textStorage?.attribute(.font, at: m.range.location, effectiveRange: nil) as? NSFont) ?? NSFont.systemFont(ofSize: 14)
            let side = (font.capHeight + 5).rounded()
            let glyphMidY = baseline(of: NSRange(location: m.range.location, length: 1), font: font) - font.capHeight / 2
            switch m.kind {
            case .checkbox(let checked):
                let box = NSRect(x: r.minX + (r.width - side) / 2, y: glyphMidY - side / 2, width: side, height: side)
                let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.75, dy: 0.75), xRadius: 4, yRadius: 4)
                path.lineWidth = 1.5
                if checked {
                    accent.setFill(); path.fill()
                    let tick = NSBezierPath()
                    tick.move(to: NSPoint(x: box.minX + side * 0.26, y: box.midY))
                    tick.line(to: NSPoint(x: box.minX + side * 0.43, y: box.minY + side * 0.70))
                    tick.line(to: NSPoint(x: box.minX + side * 0.76, y: box.minY + side * 0.30))
                    tick.lineWidth = 1.8; tick.lineCapStyle = .round; tick.lineJoinStyle = .round
                    NSColor(hex: theme.background).setStroke(); tick.stroke()
                } else {
                    NSColor(hex: theme.secondaryText).setStroke(); path.stroke()
                }
            case .bullet:
                let d = max(4, font.pointSize * 0.32)
                NSColor(hex: theme.secondaryText).setFill()
                NSBezierPath(ovalIn: NSRect(x: r.midX - d / 2, y: glyphMidY - d / 2, width: d, height: d)).fill()
            }
        }
        drawAnnotations(dirtyRect)
    }

    private func drawAnnotations(_ dirtyRect: NSRect) {
        annotationHits.removeAll()
        let theme = model.theme
        let baseFont = (typingAttributes[.font] as? NSFont) ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        for (line, a) in model.annotations {
            let base = baseline(of: line, font: baseFont)
            let color: NSColor
            switch a.kind {
            case .result: color = NSColor(hex: theme.result)
            case .error: color = NSColor(hex: theme.error)
            case .info: color = NSColor(hex: theme.secondaryText)
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: baseFont, .foregroundColor: color]
            let size = (a.text as NSString).size(withAttributes: attrs)
            let inset = textContainerOrigin.x
            let x = model.rightToLeft ? inset : bounds.width - inset - size.width
            let r = NSRect(x: x, y: base - baseFont.ascender, width: size.width, height: size.height)
            annotationHits.append((r.insetBy(dx: -4, dy: -2), a, line))
            guard r.intersects(dirtyRect) else { continue }
            NSColor(hex: theme.background).setFill()
            r.insetBy(dx: -6, dy: 0).fill()
            (a.text as NSString).draw(at: r.origin, withAttributes: attrs)
        }
    }

    // Block caret in Vim normal mode.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        guard model.blockCaret else { return super.drawInsertionPoint(in: rect, color: color, turnedOn: flag) }
        var r = rect
        let font = (typingAttributes[.font] as? NSFont) ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        r.size.width = max(("m" as NSString).size(withAttributes: [.font: font]).width, 2)
        if flag {
            color.withAlphaComponent(0.45).setFill(); r.fill()
        } else {
            setNeedsDisplay(r, avoidAdditionalLayout: true)
        }
    }

    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        var r = rect
        if model.blockCaret { r.size.width += model.lineHeight }
        super.setNeedsDisplay(r, avoidAdditionalLayout: flag)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isEditable else { return }
        for m in model.markers {
            if case .checkbox = m.kind { addCursorRect(rect(for: m.range), cursor: .pointingHand) }
        }
        for hit in annotationHits { addCursorRect(hit.rect, cursor: .pointingHand) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        editor?.applyAppearance()
    }

    // MARK: Events

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

    /// Copy/cut work without a selection (whole note / current line).
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) { return true }
        if item.action == #selector(cut(_:)) { return isEditable }
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
