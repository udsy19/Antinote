import AppKit
import UniformTypeIdentifiers
import Vision
import JotterCore

// MARK: - OCR

/// Image → text with Vision ("Drop an image to capture text.").
enum OCR {
    static func hasImage(_ pb: NSPasteboard) -> Bool { image(from: pb) != nil }

    static func image(from pb: NSPasteboard) -> CGImage? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingContentsConformToTypes: [UTType.image.identifier]]
        if let url = (pb.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first,
           let image = NSImage(contentsOf: url) {
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        guard pb.availableType(from: [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")]) != nil,
              let image = NSImage(pasteboard: pb) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Recognises text off the main thread; `completion` runs on the main thread with nil on failure.
    static func recognize(_ image: CGImage, completion: @escaping @MainActor (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            var text: String?
            if (try? handler.perform([request])) != nil {
                text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }
            DispatchQueue.main.async { completion(text) }
        }
    }
}

// MARK: - AutoPaste

/// Polls the pasteboard every 0.4 s and reports each newly copied string.
@MainActor
final class AutoPasteMonitor {
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private(set) var count = 0
    var isRunning: Bool { timer != nil }
    var onNewString: ((String) -> Void)?

    func start() {
        stop()
        count = 0
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// Ignore a pasteboard write made by the editor itself (copy/cut).
    func ignoreCurrentContents() { lastChangeCount = NSPasteboard.general.changeCount }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        count += 1
        onNewString?(s)
    }
}

// MARK: - Overlays

/// Small pill label for the Vim mode indicator.
final class PillLabel: NSView {
    let label = NSTextField(labelWithString: "")
    var fill: NSColor = .clear { didSet { layer?.backgroundColor = fill.cgColor } }

    init(fontSize: CGFloat, weight: NSFont.Weight = .medium, monospaced: Bool = false) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        label.font = monospaced ? .monospacedSystemFont(ofSize: fontSize, weight: weight) : .systemFont(ofSize: fontSize, weight: weight)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Overlays never take clicks from the text.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Shown over the note while an image is dragged in: a dashed orbit holding a small framed dot, and
/// "Drop an image to capture text." in `typeLight`.
final class DropOverlayView: NSView {
    var theme: Theme = .defaultLight { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(hex: theme.background).withAlphaComponent(0.94).setFill()
        bounds.fill()
        let ink = NSColor(hex: theme.typeLight)
        let width = bounds.width * 0.45, height = width * 479 / 700
        let art = NSRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2 - 16, width: width, height: height)
        // A tilted elliptical orbit, dashed.
        let orbit = NSBezierPath(ovalIn: NSRect(x: -width / 2, y: -height * 0.28, width: width, height: height * 0.56))
        var transform = AffineTransform(translationByX: art.midX, byY: art.midY)
        transform.rotate(byDegrees: -14)
        orbit.transform(using: transform)
        orbit.lineWidth = 1.5
        orbit.setLineDash([5, 4], count: 2, phase: 0)
        ink.setStroke()
        orbit.stroke()
        // The "image": a small rounded square with a dot, riding the orbit.
        let side = width * 0.16
        let frame = NSRect(x: art.minX + width * 0.08, y: art.midY - side * 0.2, width: side, height: side)
        NSColor(hex: theme.background).setFill()
        let square = NSBezierPath(roundedRect: frame, xRadius: side * 0.18, yRadius: side * 0.18)
        square.fill()
        square.lineWidth = 1.5
        square.stroke()
        ink.setFill()
        let d = side * 0.3
        NSBezierPath(ovalIn: NSRect(x: frame.midX - d / 2, y: frame.midY - d / 2, width: d, height: d)).fill()
        let text = "Drop an image to capture text." as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: Typography.font(size: 12), .foregroundColor: ink]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: art.maxY + 18), withAttributes: attrs)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The link hover tip: the full address and the click hints in bold white monospace on a `typeLight` rounded
/// rectangle.
final class LinkTipView: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        label.font = NSFontManager.shared.convert(Typography.font(size: 10), toHaveTrait: .boldFontMask)
        label.textColor = .white
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Places the tip with its top-right corner at `point` (in the superview), kept inside `bounds`.
    func show(_ text: String, theme: Theme, endingAt point: NSPoint, in bounds: NSRect) {
        layer?.backgroundColor = NSColor(hex: theme.typeLight).withAlphaComponent(0.9).cgColor
        label.stringValue = text
        label.preferredMaxLayoutWidth = max(120, bounds.width * 0.8 - 16)
        let size = label.fittingSize
        label.frame = NSRect(x: 8, y: 8, width: size.width, height: size.height)
        let tip = NSSize(width: size.width + 16, height: size.height + 16)
        let x = min(max(point.x - tip.width, bounds.minX + 8), bounds.maxX - tip.width - 8)
        let flipped = superview?.isFlipped ?? false
        let y = flipped ? point.y : point.y - tip.height
        frame = NSRect(x: x, y: max(bounds.minY + 4, min(y, bounds.maxY - tip.height - 4)), width: tip.width, height: tip.height)
        isHidden = false
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The `::` command list shown under the caret. Keys stay with the text view; this panel only displays and
/// accepts clicks.
@MainActor
final class CompletionPanel {
    private let panel: NSPanel
    private let list = CompletionListView()
    var items: [ExtensionCommandInfo] { list.items }
    var selectedIndex: Int { list.selected }
    var isVisible: Bool { panel.isVisible }
    var onAccept: ((ExtensionCommandInfo) -> Void)? {
        get { list.onAccept }
        set { list.onAccept = newValue }
    }

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.contentView = list
    }

    /// Shows `items` (or the empty state) under the caret, about 60% as wide as the note window.
    func show(_ items: [ExtensionCommandInfo], below screenRect: NSRect, parent: NSWindow?) {
        list.theme = Theme.current
        list.items = Array(items.prefix(8))
        list.selected = min(list.selected, max(0, list.items.count - 1))
        let width = CompletionListView.width(forWindow: parent?.frame.width ?? 400)
        let height = CompletionListView.height(rows: list.items.count)
        panel.setFrame(NSRect(x: screenRect.minX - 12, y: screenRect.minY - height - 6, width: width, height: height), display: true)
        list.needsDisplay = true
        if !panel.isVisible {
            parent?.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        list.selected = 0
    }

    func move(_ delta: Int) {
        guard !list.items.isEmpty else { return }
        list.selected = (list.selected + delta + list.items.count) % list.items.count
        list.needsDisplay = true
    }
}

/// Rows: a `›` on the selected row, the command name, a faint extension tag and an action badge
/// ("⇆ replaceLine" in accent 1, "↓ insert" in accent 3); a key-hint footer below.
final class CompletionListView: NSView {
    static let rowHeight: CGFloat = 28
    static let footerHeight: CGFloat = 26
    static func height(rows: Int) -> CGFloat { 6 + CGFloat(max(rows, 2)) * rowHeight + footerHeight }
    /// About 60% of the note window, never narrower than 280 pt.
    static func width(forWindow width: CGFloat) -> CGFloat { max(280, width * 0.6) }

    var items: [ExtensionCommandInfo] = []
    var selected = 0
    /// `background` fill with a 1 px `typeSuperlight` border, 8 pt corners.
    var theme: Theme = .defaultLight {
        didSet {
            layer?.backgroundColor = NSColor(hex: theme.background).cgColor
            layer?.borderColor = NSColor(hex: theme.typeSuperlight).cgColor
            needsDisplay = true
        }
    }
    var onAccept: ((ExtensionCommandInfo) -> Void)?
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let mono = Typography.font(size: 12), small = Typography.font(size: 10)
        let badgeFont = NSFontManager.shared.convert(Typography.font(size: 9), toHaveTrait: .boldFontMask)
        let main = NSColor(hex: theme.typeMain), faint = NSColor(hex: theme.typeSuperlight), light = NSColor(hex: theme.typeLight)
        if items.isEmpty {
            ("No commands found" as NSString).draw(at: NSPoint(x: 26, y: 12), withAttributes: [.font: mono, .foregroundColor: main])
            ("Try a different search term" as NSString).draw(at: NSPoint(x: 26, y: 12 + Self.rowHeight),
                                                             withAttributes: [.font: small, .foregroundColor: light])
        }
        for (i, item) in items.enumerated() {
            let row = NSRect(x: 0, y: 3 + CGFloat(i) * Self.rowHeight, width: bounds.width, height: Self.rowHeight)
            if i == selected {
                NSColor(hex: theme.typeHyperLight).setFill()
                row.fill()
                let chevron = NSAttributedString(string: "›", attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                                                                           .foregroundColor: main])
                chevron.draw(at: NSPoint(x: 10, y: row.midY - chevron.size().height / 2 - 1))
            }
            let (glyph, fill) = Self.badge(item.action, theme: theme)
            let badge = NSAttributedString(string: glyph + " " + item.action,
                                           attributes: [.font: badgeFont, .foregroundColor: NSColor(hex: theme.typeReverse)])
            let badgeSize = badge.size()
            let badgeRect = NSRect(x: row.maxX - 10 - badgeSize.width - 10, y: row.midY - 7.5, width: badgeSize.width + 10, height: 15)
            fill.setFill()
            NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4).fill()
            badge.draw(at: NSPoint(x: badgeRect.minX + 5, y: badgeRect.midY - badgeSize.height / 2))

            let name = NSAttributedString(string: item.name, attributes: [.font: mono, .foregroundColor: main])
            let tag = NSAttributedString(string: item.extensionName, attributes: [.font: small, .foregroundColor: faint])
            let tagX = badgeRect.minX - 10 - tag.size().width
            let showTag = tagX > 26 + name.size().width + 8
            if showTag { tag.draw(at: NSPoint(x: tagX, y: row.midY - tag.size().height / 2)) }
            let nameRect = NSRect(x: 26, y: row.midY - name.size().height / 2, width: (showTag ? tagX : badgeRect.minX) - 34,
                                  height: name.size().height)
            name.draw(with: nameRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        let footer = NSRect(x: 0, y: bounds.height - Self.footerHeight, width: bounds.width, height: Self.footerHeight)
        NSColor(hex: theme.typeHyperLight).setFill()
        NSRect(x: 0, y: footer.minY, width: bounds.width, height: 1).fill()
        let hint = NSAttributedString(string: "↑↓ to navigate · ⇥ or ↩ to select",
                                      attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: light])
        hint.draw(at: NSPoint(x: 18, y: footer.midY - hint.size().height / 2))
    }

    /// The badge glyph and fill for a command's action.
    static func badge(_ action: String, theme: Theme) -> (String, NSColor) {
        switch action {
        case "insert": ("↓", NSColor(hex: theme.accent3Main))
        case "openURL": ("↗", NSColor(hex: theme.accent4Main))
        default: ("⇆", NSColor(hex: theme.accent1Main))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = Int((p.y - 3) / Self.rowHeight)
        guard items.indices.contains(i), p.y < bounds.height - Self.footerHeight else { return }
        selected = i
        onAccept?(items[i])
    }
}

/// Offscreen views for rendering (JotterRender); nothing here is shown on screen.
public enum EditorPreview {
    /// The `::` command list as it appears under the caret in a note window `width` points wide.
    @MainActor public static func completionList(_ items: [ExtensionCommandInfo], selected: Int = 0, width: CGFloat) -> NSView {
        let list = CompletionListView(frame: NSRect(x: 0, y: 0, width: CompletionListView.width(forWindow: width),
                                                    height: CompletionListView.height(rows: min(items.count, 8))))
        list.theme = Theme.current
        list.items = Array(items.prefix(8))
        list.selected = selected
        return list
    }

    /// The link hover tip, top-right corner at `point` inside `bounds`.
    @MainActor public static func linkTip(_ text: String, endingAt point: NSPoint, in bounds: NSRect) -> NSView {
        let tip = LinkTipView()
        tip.show(text, theme: Theme.current, endingAt: point, in: bounds)
        return tip
    }
}
