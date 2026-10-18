import AppKit
import os

public enum Log {
    public static let app = Logger(subsystem: SuperNotesPaths.bundleID, category: "app")
    public static let store = Logger(subsystem: SuperNotesPaths.bundleID, category: "store")
    public static let extensions = Logger(subsystem: SuperNotesPaths.bundleID, category: "extensions")
    public static let sync = Logger(subsystem: SuperNotesPaths.bundleID, category: "sync")
    public static let updates = Logger(subsystem: SuperNotesPaths.bundleID, category: "updates")
}

// MARK: - Alerts & HUD

@MainActor
public enum Alerts {
    public static func error(_ message: String, _ error: Error? = nil) {
        Log.app.error("\(message, privacy: .public) \(error?.localizedDescription ?? "", privacy: .public)")
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = message
        if let error { a.informativeText = error.localizedDescription }
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    /// Confirmation with optional "Don't ask again" suppression (reset via Settings → Advanced).
    public static func confirm(_ message: String, info: String = "", confirmTitle: String = "OK",
                               cancelTitle: String = "Cancel", destructive: Bool = false, suppressionID: String? = nil) -> Bool {
        if let id = suppressionID, Defaults[.suppressedWarnings].contains(id) { return true }
        let a = NSAlert()
        a.messageText = message
        a.informativeText = info
        let ok = a.addButton(withTitle: confirmTitle)
        if destructive { ok.hasDestructiveAction = true }
        a.addButton(withTitle: cancelTitle)
        if suppressionID != nil { a.showsSuppressionButton = true; a.suppressionButton?.title = "Don't ask again." }
        NSApp.activate(ignoringOtherApps: true)
        let result = a.runModal() == .alertFirstButtonReturn
        if result, let id = suppressionID, a.suppressionButton?.state == .on { Defaults[.suppressedWarnings].insert(id) }
        return result
    }

    /// Text prompt; returns nil on cancel.
    public static func prompt(title: String, message: String = "", defaultValue: String = "") -> String? {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = defaultValue
        a.accessoryView = field
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        let v = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? defaultValue : v
    }
}

/// What a message pill reports; picks its fill colour.
public enum PillKind: Sendable {
    /// Neutral (`typeMain` fill): "Empty note deleted", "Timer paused".
    case info
    /// `accent1Main` fill: "Stopwatch started", "Extracted text."
    case success
    /// `accent4Main` fill.
    case warning
    /// `accent5Main` fill.
    case error

    public func fill(_ theme: Theme) -> NSColor {
        switch self {
        case .info: NSColor(hex: theme.typeMain)
        case .success: NSColor(hex: theme.accent1Main)
        case .warning: NSColor(hex: theme.accent4Main)
        case .error: NSColor(hex: theme.accent5Main)
        }
    }
}

/// A message pill: editor-font text in `typeReverse`, padded 15 × 5 pt, in its kind's colour — a capsule for one
/// line. A long message wraps at `maxWidth` (the host's text column) to at most three lines, then is cut short with
/// "…" and the whole message goes in the tooltip; the pill grows taller, never wider, so it can't widen the window.
/// It fades in (100 ms), holds for one second plus 50 ms per character and fades out (500 ms); it never takes clicks
/// (only a cut-short one takes the pointer, for its tooltip).
@MainActor
public final class PillView: NSView {
    public static let bottomInset: CGFloat = 20
    /// Below the top bar when the pill has to move up.
    public static let topInset: CGFloat = 44
    public static let maxLines = 3
    static let padding = NSSize(width: 15, height: 5)
    /// The widest the pill gets.
    public var maxWidth: CGFloat = 320 {
        didSet { if maxWidth != oldValue { widthLimit.constant = maxWidth; fit() } }
    }
    private let label = NSTextField(labelWithString: "")
    private lazy var widthLimit = widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth)
    private var hideWork: DispatchWorkItem?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        alphaValue = 0
        label.maximumNumberOfLines = Self.maxLines
        label.lineBreakMode = .byWordWrapping
        label.cell?.truncatesLastVisibleLine = true
        // Below the window's own size (NSLayoutPriorityWindowSizeStayPut, 500): text wraps, it never widens the window.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        let p = Self.padding
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: p.width),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -p.width),
            label.topAnchor.constraint(equalTo: topAnchor, constant: p.height),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -p.height),
        ])
        widthLimit.isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.height / 2, 14)
    }

    /// Wraps the text at `maxWidth`; a message longer than `maxLines` lines keeps its whole text in the tooltip.
    private func fit() {
        let width = max(40, maxWidth - 2 * Self.padding.width)
        label.preferredMaxLayoutWidth = width
        let font = label.font ?? Typography.font()
        let needed = (label.stringValue as NSString).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                                                  options: [.usesLineFragmentOrigin], attributes: [.font: font]).height
        let lines = needed / NSLayoutManager().defaultLineHeight(for: font)
        toolTip = lines > CGFloat(Self.maxLines) + 0.5 ? label.stringValue : nil
        label.invalidateIntrinsicContentSize()
    }

    /// How long a message stays up: one second plus 50 ms per character.
    public nonisolated static func duration(for message: String) -> TimeInterval { 1 + 0.05 * Double(message.count) }

    /// Sets the text and colours without animating (used directly by offscreen renders).
    public func configure(_ text: String, kind: PillKind, theme: Theme) {
        label.stringValue = text
        label.font = Typography.font()
        label.alignment = text.contains("\n") ? .left : .center
        label.textColor = NSColor(hex: theme.typeReverse)
        layer?.backgroundColor = kind.fill(theme).cgColor
        fit()
    }

    /// Shows `text` for `duration` seconds (by default `duration(for:)`), then fades out.
    public func show(_ text: String, kind: PillKind = .info, theme: Theme, duration: TimeInterval? = nil,
                     completion: (@MainActor @Sendable () -> Void)? = nil) {
        configure(text, kind: kind, theme: theme)
        hideWork?.cancel()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.1; animator().alphaValue = 1 }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.5; self.animator().alphaValue = 0 }) {
                    MainActor.assumeIsolated { completion?() }
                }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (duration ?? Self.duration(for: text)), execute: work)
    }

    /// Clicks go through to what's under it; a cut-short message takes the pointer while shown, for its tooltip.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        toolTip != nil && alphaValue > 0.01 && frame.contains(point) ? self : nil
    }
}

/// App-wide message pill, centred 20 pt above the bottom of the key Super Notes window (or low on the active screen
/// when no window is key).
@MainActor
public enum HUD {
    private static var panel: NSPanel?

    public static func show(_ text: String, kind: PillKind = .info) {
        panel?.parent?.removeChildWindow(panel!)
        panel?.orderOut(nil)
        let pill = PillView()
        let host = NSApp.keyWindow.flatMap { $0.isVisible && $0.styleMask.contains(.titled) ? $0 : nil }
        let area = host?.frame ?? NSScreen.active.visibleFrame
        pill.maxWidth = min(area.width - 40, 480)   // a long message wraps instead of running past the window
        pill.configure(text, kind: kind, theme: Theme.current)
        let size = pill.fittingSize
        let frame = NSRect(x: area.midX - size.width / 2,
                           y: area.minY + (host == nil ? area.height * 0.15 : PillView.bottomInset),
                           width: size.width, height: size.height)
        let w = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.level = .statusBar; w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.contentView = pill
        host?.addChildWindow(w, ordered: .above)
        w.orderFrontRegardless()
        panel = w
        pill.show(text, kind: kind, theme: Theme.current) {
            w.parent?.removeChildWindow(w)
            w.orderOut(nil)
        }
    }
}

public extension NSScreen {
    /// The screen containing the mouse cursor.
    static var active: NSScreen {
        let p = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(p, $0.frame, false) } ?? main ?? screens[0]
    }
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }
    static func with(displayID: CGDirectDisplayID) -> NSScreen? { screens.first { $0.displayID == displayID } }
}

