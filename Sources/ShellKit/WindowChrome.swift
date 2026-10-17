import AppKit
import JotterCore

// Views that make up the main note window: title bar, slots bar, bottom bar, note panes and the lock screen.

/// The main note window: titled (resizable, shadowed) with a transparent full-size title bar.
final class MainWindow: NSWindow {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        title = "Jotter"
        minSize = NSSize(width: 240, height: 180)
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenPrimary, .moveToActiveSpace]
        tabbingMode = .disallowed
    }

    var trafficLights: [NSButton] {
        [.closeButton, .miniaturizeButton, .zoomButton].compactMap { standardWindowButton($0) }
    }
}

/// Small borderless symbol button used in the window chrome.
@MainActor
func chromeButton(_ symbol: String, _ tooltip: String, target: AnyObject?, action: Selector) -> NSButton {
    let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage(),
                     target: target, action: action)
    b.isBordered = false
    b.bezelStyle = .regularSquare
    b.imageScaling = .scaleProportionallyDown
    b.symbolConfiguration = .init(pointSize: 12, weight: .medium)
    b.toolTip = tooltip
    b.setAccessibilityLabel(tooltip)
    b.translatesAutoresizingMaskIntoConstraints = false
    b.widthAnchor.constraint(equalToConstant: 22).isActive = true
    b.heightAnchor.constraint(equalToConstant: 20).isActive = true
    return b
}

/// Top strip: drags the window, and reveals its buttons (and the traffic lights) while hovered.
final class TitleBarView: NSView {
    static let height: CGFloat = 28
    let pinButton: NSButton
    private let buttons: NSStackView
    var onHoverChange: ((Bool) -> Void)?

    init(target: AnyObject) {
        pinButton = chromeButton("pin", "Pin on Top", target: target, action: #selector(Shell.togglePin(_:)))
        let more = chromeButton("ellipsis.circle", "More", target: target, action: #selector(Shell.showMoreMenu(_:)))
        buttons = NSStackView(views: [
            chromeButton("plus", "New Note", target: target, action: #selector(Shell.newNote(_:))),
            chromeButton("rectangle.split.2x1", "Split View", target: target, action: #selector(Shell.toggleSplit(_:))),
            pinButton,
            chromeButton("gearshape", "Settings", target: target, action: #selector(Shell.openSettings(_:))),
            more,
        ])
        super.init(frame: .zero)
        buttons.spacing = 2
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.alphaValue = 0
        addSubview(buttons)
        NSLayoutConstraint.activate([
            buttons.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            buttons.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { setRevealed(true) }
    override func mouseExited(with event: NSEvent) { setRevealed(false) }

    func setRevealed(_ revealed: Bool) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            buttons.animator().alphaValue = revealed ? 1 : 0
        }
        onHoverChange?(revealed)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
    }

    func apply(theme: Theme) {
        for case let b as NSButton in buttons.arrangedSubviews { b.contentTintColor = NSColor(hex: theme.secondaryText) }
    }

    func setPinned(_ pinned: Bool) {
        pinButton.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: "Pin on Top")
        pinButton.toolTip = pinned ? "Unpin from Top" : "Pin on Top"
    }
}

/// Row of slot chips: ∞ (the deck) and 1…9.
final class SlotsBarView: NSView {
    static let height: CGFloat = 24
    private let stack = NSStackView()
    private var chips: [NSButton] = []
    var onSelect: ((Int?) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        for i in -1..<SlotBoard.count {
            let b = NSButton(title: i < 0 ? "∞" : "\(i + 1)", target: self, action: #selector(chipClicked(_:)))
            b.tag = i
            b.isBordered = false
            b.wantsLayer = true
            b.layer?.cornerRadius = 5
            b.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 22).isActive = true
            b.heightAnchor.constraint(equalToConstant: 18).isActive = true
            chips.append(b)
            stack.addArrangedSubview(b)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func chipClicked(_ sender: NSButton) { onSelect?(sender.tag < 0 ? nil : sender.tag) }

    /// `titles[slot]` is the occupant's title; `open` is the slot shown (nil = deck).
    func update(titles: [Int: String], open: Int?, theme: Theme) {
        let text = NSColor(hex: theme.text), secondary = NSColor(hex: theme.secondaryText), accent = NSColor(hex: theme.accent)
        for b in chips {
            let slot: Int? = b.tag < 0 ? nil : b.tag
            let selected = slot == open
            let occupied = slot.map { titles[$0] != nil } ?? true
            b.attributedTitle = NSAttributedString(string: b.title, attributes: [
                .font: b.font ?? NSFont.systemFont(ofSize: 11),
                .foregroundColor: selected ? accent : (occupied ? text : secondary.withAlphaComponent(0.5)),
            ])
            b.layer?.backgroundColor = selected ? accent.withAlphaComponent(0.15).cgColor : nil
            if let slot {
                b.toolTip = titles[slot].map { "Slot \(slot + 1): \($0.isEmpty ? "Empty note" : $0)" }
                    ?? "Slot \(slot + 1) is free — click to put this note here"
            } else {
                b.toolTip = "Ephemeral notes"
            }
        }
    }
}

/// Bottom strip: mode summary, optional date, position "3 / 12" and the latest-note dot.
final class BottomBarView: NSView {
    static let height: CGFloat = 22
    private let summary = NSTextField(labelWithString: "")
    let position: NSButton
    private let dot = NSView()

    init(target: AnyObject) {
        position = NSButton(title: "", target: target, action: #selector(Shell.goToFirstNote(_:)))
        super.init(frame: .zero)
        position.isBordered = false
        position.toolTip = "Go to the latest note"
        summary.font = .systemFont(ofSize: 11)
        summary.lineBreakMode = .byTruncatingTail
        summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        for v in [summary, position, dot] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            summary.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            summary.centerYAnchor.constraint(equalTo: centerYAnchor),
            summary.trailingAnchor.constraint(lessThanOrEqualTo: position.leadingAnchor, constant: -8),
            dot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6), dot.heightAnchor.constraint(equalToConstant: 6),
            position.trailingAnchor.constraint(equalTo: dot.leadingAnchor, constant: -6),
            position.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(summary text: String, position pos: String, latest: Bool, theme: Theme) {
        let secondary = NSColor(hex: theme.secondaryText)
        summary.stringValue = text
        summary.textColor = secondary
        position.attributedTitle = NSAttributedString(string: pos, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: secondary,
        ])
        dot.isHidden = !(latest && Defaults[.showLatestNoteIndicator])
        dot.layer?.backgroundColor = NSColor(hex: theme.accent).cgColor
    }
}

/// One editor plus the lock screen that replaces it for locked notes.
final class NotePane: NSView {
    let editor: NoteEditing
    private(set) var noteID: UUID?
    private let lockView: LockScreenView

    init(editor: NoteEditing, onUnlock: @escaping () -> Void) {
        self.editor = editor
        lockView = LockScreenView(onUnlock: onUnlock)
        super.init(frame: .zero)
        for v in [editor.view, lockView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: leadingAnchor), v.trailingAnchor.constraint(equalTo: trailingAnchor),
                v.topAnchor.constraint(equalTo: topAnchor), v.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        lockView.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }

    var isShowingLock: Bool { !lockView.isHidden }

    func show(_ note: Note, locked: Bool) {
        if note.id != noteID || editor.note?.id != note.id { editor.load(note) }
        noteID = note.id
        editor.view.isHidden = locked
        lockView.isHidden = !locked
    }

    func clear() { noteID = nil }

    func apply(theme: Theme) { lockView.apply(theme: theme) }

    func contains(responder: NSResponder?) -> Bool {
        guard let view = responder as? NSView else { return false }
        return view.isDescendant(of: self)
    }
}

final class LockScreenView: NSView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "This note is locked")
    private let button: NSButton
    private let onUnlock: () -> Void

    init(onUnlock: @escaping () -> Void) {
        self.onUnlock = onUnlock
        button = NSButton(title: "Unlock", target: nil, action: nil)
        super.init(frame: .zero)
        button.target = self
        button.action = #selector(unlock)
        button.bezelStyle = .push
        button.keyEquivalent = "\r"
        icon.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked")
        icon.symbolConfiguration = .init(pointSize: 28, weight: .regular)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        let stack = NSStackView(views: [icon, label, button])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: centerXAnchor),
                                     stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func unlock() { onUnlock() }

    func apply(theme: Theme) {
        icon.contentTintColor = NSColor(hex: theme.secondaryText)
        label.textColor = NSColor(hex: theme.text)
    }
}
