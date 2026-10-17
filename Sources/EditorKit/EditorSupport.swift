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

/// Small pill label used for toasts, the summary and the Vim mode indicator.
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
        let fx = NSVisualEffectView()
        fx.material = .menu; fx.state = .active; fx.wantsLayer = true; fx.layer?.cornerRadius = 8; fx.layer?.masksToBounds = true
        list.autoresizingMask = [.width, .height]
        fx.addSubview(list)
        panel.contentView = fx
    }

    func show(_ items: [ExtensionCommandInfo], below screenRect: NSRect, parent: NSWindow?) {
        guard !items.isEmpty else { return hide() }
        list.items = Array(items.prefix(8))
        list.selected = min(list.selected, list.items.count - 1)
        let height = CGFloat(list.items.count) * CompletionListView.rowHeight + 8
        panel.setFrame(NSRect(x: screenRect.minX, y: screenRect.minY - height - 4, width: 340, height: height), display: true)
        list.frame = panel.contentView?.bounds ?? .zero
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

private final class CompletionListView: NSView {
    static let rowHeight: CGFloat = 38
    var items: [ExtensionCommandInfo] = []
    var selected = 0
    var onAccept: ((ExtensionCommandInfo) -> Void)?
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        for (i, item) in items.enumerated() {
            let row = NSRect(x: 4, y: 4 + CGFloat(i) * Self.rowHeight, width: bounds.width - 8, height: Self.rowHeight)
            if i == selected {
                NSColor.selectedContentBackgroundColor.setFill()
                NSBezierPath(roundedRect: row, xRadius: 5, yRadius: 5).fill()
            }
            let primary: NSColor = i == selected ? .alternateSelectedControlTextColor : .labelColor
            let secondary: NSColor = i == selected ? .alternateSelectedControlTextColor.withAlphaComponent(0.8) : .secondaryLabelColor
            let title = item.signature.isEmpty ? "::" + item.name : item.signature
            (title as NSString).draw(at: NSPoint(x: row.minX + 8, y: row.minY + 3),
                                     withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: primary])
            let help = item.helpText.isEmpty ? item.extensionName : item.helpText
            (help as NSString).draw(with: NSRect(x: row.minX + 8, y: row.minY + 20, width: row.width - 16, height: 15),
                                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                    attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: secondary])
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = Int((p.y - 4) / Self.rowHeight)
        guard items.indices.contains(i) else { return }
        selected = i
        onAccept?(items[i])
    }
}
