import AppKit
import Combine
import LocalAuthentication
import SuperNotesCore

/// The main note window and everything it does: deck navigation, slots, split view, locking and the menu actions.
@MainActor
final class Shell: NSObject, WindowServicing, NSWindowDelegate, NSMenuItemValidation, NSMenuDelegate {
    static let shared = Shell()

    enum Role { case ephemeral, slot }

    let window = MainWindow()
    private var ephemeralPane: NotePane!
    private var slotPane: NotePane!
    private var titleBar: TitleBarView!
    private var slotsBar: SlotsBarView!
    private var slotsBarBottom: NSLayoutConstraint!
    private var bottomBar: BottomBarView!
    private let latestDot = NSView()
    /// Whether the slot bar is up: hover dwell, slot navigation, always-show, and never while typing.
    private var slotBarState = SlotBarVisibility(alwaysShow: Defaults[.alwaysShowSlotsBar])
    private var slotBarWork: DispatchWorkItem?
    /// Where the pointer rested when a keystroke hid the slot bar; it must really move (4 pt) to count again.
    private var pointerRest: NSPoint?
    private let paneContainer = NSView()
    private let effectView = NSVisualEffectView()
    private let tintView = NSView()
    /// A view shown over the note area (`present(inWindow:)`), e.g. Search.
    private var presented: NSView?

    /// Slot shown in the single-pane slotted view or in the slotted half of the split.
    private var openSlot: Int?
    private var analyses: [Role: NoteAnalysis] = [:]
    private var relock = RelockSession()
    private var swipe = SwipeAccumulator(sensitivity: 0.5)
    private var authInFlight = false
    private var refreshScheduled = false
    private var launched = false
    private var cancellables: Set<AnyCancellable> = []
    private var observations: [NSKeyValueObservation] = []
    private var timers: [Timer] = []
    /// Asks for Touch ID once a locked note has stayed on screen (Settings → Notes → Ask to unlock automatically).
    private var autoUnlockWork: DispatchWorkItem?
    /// The theme the chrome was last painted with (slotted notes can have their own).
    private var appliedThemeID = ""
    /// Holds "Undo Delete Note" until the next edit or navigation; the editors route ⌘Z here while it does.
    private let noteUndo = UndoManager()
    /// The store the preview window was last built for (`prepareForPreview`); set, the window is an offscreen
    /// preview that is never ordered front.
    private var previewStoreID: ObjectIdentifier?
    private var isPreview: Bool { previewStoreID != nil }

    private var store: NoteStoring { Services.store }
    private var isSplit: Bool { Defaults[.shellKitSplit] }

    // MARK: - Launch

    func launch() {
        guard !launched else { return }
        launched = true
        // A silent relaunch into an update puts everything back the way it was, without taking focus.
        let relaunch = Defaults[.updateRelaunch]
        if relaunch != nil { Defaults[.updateRelaunch] = nil }
        buildWindow()
        Onboarding.runIfNeeded()
        restoreCurrentNote(startFresh: relaunch == nil && Defaults[.startWithNewNote])
        observe()
        Presence.shared.start()
        AppIcons.apply()
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleReopen(_:reply:)),
                                                     forEventClass: AEEventClass(kCoreEventClass),
                                                     andEventID: AEEventID(kAEReopenApplication))
        switch relaunch {
        case .visible?:
            Presence.shared.positionDropdown(window)
            window.orderFrontRegardless()
            window.alignTrafficLights()
        case .hidden?: break
        case nil: if !Presence.shared.isDropdown { showMain() }
        }
    }

    @objc private func handleReopen(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) { showMain() }

    /// Renders and self-tests: an editor command on the shown note, and where the Typing button sits in the
    /// window's frame view (the menu facsimile goes under it).
    func performForPreview(_ command: EditorCommand) { pane(activeRole).editor.perform(command) }
    var typingButtonFrameInFrame: NSRect {
        let frame = window.contentView?.superview ?? window.contentView!
        return titleBar.typingButton.convert(titleBar.typingButton.bounds, to: frame)
    }

    /// Builds the window without showing it (offscreen renders): the front note, or `slot`, with the hover bars
    /// pinned visible when `revealed`, the content `size` (the default when nil), the pointer resting on the slot
    /// bar's `hoveredSlot`, and the slot bar as `slotBar` has it. Returns the window's frame view.
    func prepareForPreview(revealed: Bool, slot: Int?, size: NSSize? = nil, hoveredSlot: Int? = nil,
                           slotBar: WindowPreview.SlotBar = .natural, presenting: NSView? = nil) -> NSView {
        if !launched {
            launched = true
            MainMenu.buildForPreview()
            buildWindow()
            restoreCurrentNote()
        }
        // Self-tests swap the store between cases: the window follows the store it is now pointed at.
        let storeID = ObjectIdentifier(store as AnyObject)
        if previewStoreID != nil, previewStoreID != storeID { reloadForPreview() }
        previewStoreID = storeID
        if presenting !== presented { present(inWindow: presenting) }
        window.setContentSize(size ?? MainWindow.defaultSize)
        slotsBar.setHovered(hoveredSlot)   // before the slot opens: a planet under the pointer keeps its tip
        if let slot { openSlot(slot) }
        applyTheme()
        titleBar.pinnedVisible = revealed
        bottomBar.pinnedVisible = revealed
        window.trafficLights.forEach { $0.alphaValue = revealed ? 1 : 0 }
        let now = Date()
        switch slotBar {
        case .natural: break
        case .hovering:
            // The pointer has rested in the bottom strip for longer than the dwell.
            slotBarState.handle(.pointer(inZone: true), at: now.addingTimeInterval(-1))
        case .typing:
            slotBarState.handle(.keystroke, at: now)
        case .hidden:
            slotBarState = SlotBarVisibility(alwaysShow: Defaults[.alwaysShowSlotsBar])
        }
        refreshChrome()
        let frame = window.contentView?.superview ?? window.contentView!
        frame.layoutSubtreeIfNeeded()
        window.alignTrafficLights()
        return frame
    }

    private func buildWindow() {
        let root = RootView()
        root.onPointer = { [weak self] point in self?.pointerMoved(to: point) }
        titleBar = TitleBarView(target: self)
        titleBar.onHoverChange = { [weak self] revealed in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = HoverBar.fadeDuration
                self?.window.trafficLights.forEach { $0.animator().alphaValue = revealed ? 1 : 0 }
            }
        }
        slotsBar = SlotsBarView()
        slotsBar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        slotsBar.onSelect = { [weak self] slot in self?.slotChipClicked(slot) }
        slotsBar.contextMenu = { [weak self] slot in self?.slotMenu(slot) }
        bottomBar = BottomBarView(target: self)
        bottomBar.onHoverChange = { [weak self] _ in self?.refreshChrome() }
        // The slot bar sits above the revealed bottom bar: moving onto it keeps both up. While it rests low (always
        // shown, bottom bar hidden), hovering it doesn't raise the bottom bar, so it never jumps from under the pointer.
        slotsBar.onHoverChange = { [weak self] hovering in self?.bottomBar.hold(hovering) }
        bottomBar.lingers = 0.25
        bottomBar.revealExcluded = { [weak self] point in
            guard let bar = self?.slotsBar, bar.isShown, let root = bar.superview else { return false }
            return bar.frame.contains(root.convert(point, from: nil))
        }
        effectView.material = .underWindowBackground
        effectView.blendingMode = .behindWindow
        effectView.state = .followsWindowActiveState
        tintView.wantsLayer = true
        latestDot.wantsLayer = true
        latestDot.layer?.cornerRadius = Self.latestDotSize / 2

        // The note fills the window; the bars float over it.
        for v in [effectView, tintView, paneContainer, latestDot, bottomBar, slotsBar, titleBar] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        var constraints: [NSLayoutConstraint] = []
        for v in [effectView, tintView, paneContainer] as [NSView] {
            constraints += [v.leadingAnchor.constraint(equalTo: root.leadingAnchor), v.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                            v.topAnchor.constraint(equalTo: root.topAnchor), v.bottomAnchor.constraint(equalTo: root.bottomAnchor)]
        }
        for v in [titleBar, bottomBar] as [NSView] {
            constraints += [v.leadingAnchor.constraint(equalTo: root.leadingAnchor), v.trailingAnchor.constraint(equalTo: root.trailingAnchor)]
        }
        slotsBarBottom = slotsBar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -SlotsBarView.bottomInset)
        constraints += [
            titleBar.topAnchor.constraint(equalTo: root.topAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: TitleBarView.height),
            bottomBar.heightAnchor.constraint(equalToConstant: BottomBarView.height),
            bottomBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            slotsBar.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            // In a window narrower than the bar it shrinks, 8 pt from each side.
            slotsBar.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -16),
            slotsBar.heightAnchor.constraint(equalToConstant: SlotsBarView.height),
            slotsBarBottom,
            latestDot.widthAnchor.constraint(equalToConstant: Self.latestDotSize),
            latestDot.heightAnchor.constraint(equalToConstant: Self.latestDotSize),
            latestDot.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Self.latestDotInset),
            latestDot.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Self.latestDotInset),
        ]
        NSLayoutConstraint.activate(constraints)
        window.contentView = root
        window.delegate = self
        window.trafficLights.forEach { $0.alphaValue = 0 }

        ephemeralPane = makePane(.ephemeral)
        slotPane = makePane(.slot)
        if !window.setFrameUsingName("SuperNotesMainWindow") { window.center() }
        window.alignTrafficLights()
        layoutPanes()
        applyTheme()
    }

    private func makePane(_ role: Role) -> NotePane {
        let editor = Services.editorFactory.makeEditor()
        let pane = NotePane(editor: editor) { [weak self] in self?.requestUnlock(role) }
        editor.onAnalysis = { [weak self] analysis in
            self?.analyses[role] = analysis
            self?.refreshChrome()
            self?.forgetUndoDelete()   // typing moves on; the deleted note stays in The Void
        }
        editor.onBottomControlsChange = { [weak self] in self?.refreshChrome() }
        editor.externalUndo = { [weak self] in
            guard let self, self.noteUndo.canUndo else { return nil }
            return self.noteUndo
        }
        return pane
    }

    /// Offers "Undo <name>" (⌘Z in the note) until the next edit or move: `undo` puts things back.
    private func offerUndo(_ name: String, _ undo: @escaping @MainActor (Shell) -> Void) {
        noteUndo.removeAllActions()
        noteUndo.groupsByEvent = false
        noteUndo.beginUndoGrouping()
        defer { noteUndo.endUndoGrouping() }
        noteUndo.registerUndo(withTarget: self) { shell in MainActor.assumeIsolated { undo(shell) } }
        noteUndo.setActionName(name)
    }

    /// Delete Note, undone: the note comes back from The Void and is shown again.
    private func offerUndoDelete(_ id: UUID) {
        offerUndo("Delete Note") { shell in
            guard shell.store.note(id)?.isInVoid == true else { return }
            shell.store.restoreFromVoid(id)
            shell.showEphemeral(id)   // restored notes rejoin the deck at the front
            HUD.show("Note restored", kind: .success)
        }
    }

    private func flushEditors() {
        ephemeralPane.editor.flush()
        slotPane.editor.flush()
    }

    private func observe() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushEditors() }
        }
        store.changes.sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &cancellables)
        let themeKeys: [Defaults.Keys] = [.lightTheme, .darkTheme, .slottedLightTheme, .slottedDarkTheme, .translucent,
                                          .translucencyOpacity, .solidBarsWhenTranslucent]
        Defaults.changes
            .filter { name in themeKeys.contains { $0.name == name } }
            .sink { [weak self] _ in self?.applyTheme() }.store(in: &cancellables)
        let chromeKeys: [Defaults.Keys] = [.showLatestNoteIndicator, .showNoteDates, .alwaysShowSlotsBar, .showBottomBar,
                                           .showNoteCount, .showCreationDate]
        Defaults.changes
            .filter { name in chromeKeys.contains { $0.name == name } }
            .sink { [weak self] _ in self?.refreshChrome() }.store(in: &cancellables)
        Defaults.changes
            .filter { $0 == Defaults.Keys.showArchivedInStack.name }
            .sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &cancellables)
        Defaults.changes
            .filter { ["shellKitSplit", "shellKitSplitHorizontal", "shellKitSwapPanes"].contains($0) }
            .sink { [weak self] _ in self?.splitChanged() }.store(in: &cancellables)
        NotificationCenter.default.addObserver(forName: Theme.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyTheme() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Defaults[.shellKitLastHidden] = Date().timeIntervalSince1970 }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.returnedAfterInactivity() }
        }
        observations.append(NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.applyTheme() } }
        })
        observations.append(window.observe(\.firstResponder) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.focusMoved() } }
        })
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let swallow = MainActor.assumeIsolated { self?.swallowsScroll(event) ?? false }
            return swallow ? nil : event
        }
        // Typing into the note (a plain keystroke, not a shortcut) takes the hover bars and the slot bar down so
        // they never sit over the text being written.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.window, !event.modifierFlags.contains(.command),
                      self.window.firstResponder is NSTextView else { return }
                let point = self.window.mouseLocationOutsideOfEventStream
                self.titleBar.typingStarted(pointerAt: point)
                self.bottomBar.typingStarted(pointerAt: point)
                self.pointerRest = self.window.contentView?.convert(point, from: nil)
                self.slotBar(.keystroke)
            }
            return event
        }
        timers.append(Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        })
    }

    /// The note Super Notes opens on: a fresh one with "Start with a new note" (`startFresh`), else the last note
    /// shown; the first slotted note with "Use slotted notes as your main notes".
    private func restoreCurrentNote(startFresh: Bool = Defaults[.startWithNewNote]) {
        let deck = ephemeralDeck()
        if startFresh {
            if let front = deck.first, DeckNavigator.isBlank(front.content) { showEphemeral(front.id) } else { createNote() }
        } else if let id = UUID(uuidString: Defaults[.shellKitCurrentNote]), deck.contains(where: { $0.id == id }) {
            showEphemeral(id)
        } else if let front = deck.first {
            showEphemeral(front.id)
        } else {
            createNote()
        }
        if Defaults[.slottedAsMain], !startFresh, let first = board().occupants.keys.min() { openSlot(first) }
    }

    // MARK: - WindowServicing

    /// Nil until the window is built.
    var currentNoteID: UUID? { ephemeralPane == nil ? nil : pane(activeRole).noteID }
    var isMainWindowVisible: Bool { window.isVisible }
    var isMainWindowKey: Bool { window.isKeyWindow && NSApp.isActive }
    var hasUnsavedEdits: Bool { ephemeralPane != nil && (ephemeralPane.editor.hasUnsavedChanges || slotPane.editor.hasUnsavedChanges) }
    func flushEdits() { if ephemeralPane != nil { flushEditors() } }

    func showMain() {
        if !window.isVisible { startFreshIfInactive() }
        checkRelock()
        Presence.shared.positionDropdown(window)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.alignTrafficLights()
        focusActive()
        scheduleAutoUnlock()
    }

    func toggleMain() {
        if window.isVisible && window.isKeyWindow && NSApp.isActive { hideMain() } else { showMain() }
    }

    func show(noteID: UUID) {
        guard store.note(noteID) != nil else { return }
        reveal(noteID)
        showMain()
    }

    func showSettings(tab: String?) {
        SettingsWindow.shared.show(tab: SettingsTab(routing: tab))
    }

    /// The presented view owns the bottom strip: the bottom bar, the slot bar and the latest-note dot stay down
    /// while it shows (`refreshChrome`), so its own controls never meet the note's.
    func present(inWindow view: NSView?) {
        presented?.removeFromSuperview()
        presented = view
        guard let view, let root = window.contentView else { refreshChrome(); focusActive(); return }
        view.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(view, positioned: .below, relativeTo: latestDot)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: root.leadingAnchor), view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            view.topAnchor.constraint(equalTo: root.topAnchor), view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        refreshChrome()
        if !window.isVisible, !isPreview { showMain() }
    }

    /// Whether a mode's own controls hold the bottom strip right now: a presented view (Search) or an editor's
    /// find shelf. The bottom bar and the slot bar stay down while they do.
    private var bottomStripTaken: Bool {
        presented != nil || [ephemeralPane, slotPane].contains { $0?.window != nil && $0?.editor.hasBottomControls == true }
    }

    func hideMain() {
        flushEditors()
        Defaults[.shellKitLastHidden] = Date().timeIntervalSince1970
        window.orderOut(nil)
        relock.setFocused(false, at: Date())
        let othersVisible = NSApp.windows.contains { $0 !== window && $0.isVisible && $0.styleMask.contains(.titled) }
        if NSApp.isActive && !othersVisible { NSApp.hide(nil) }
    }

    // MARK: - Deck

    /// Non-slotted notes, front first; archived notes follow at the back with "Show archived notes in the note stack".
    private func ephemeralDeck() -> [Note] {
        (Defaults[.showArchivedInStack] ? store.deck + store.archived : store.deck).filter { $0.slot == nil }
    }
    private func board() -> SlotBoard { SlotBoard(notes: store.deck.map { ($0.id, $0.slot) }) }
    private func slotNote(_ slot: Int) -> Note? { store.deck.first { $0.slot == slot } }

    private func pane(_ role: Role) -> NotePane { role == .slot ? slotPane : ephemeralPane }

    private var activeRole: Role {
        if isSplit { return slotPane.contains(responder: window.firstResponder) ? .slot : .ephemeral }
        return openSlot != nil ? .slot : .ephemeral
    }

    /// The stored note merged with the editor's latest text (the editor may not have saved yet).
    private func freshNote(_ id: UUID) -> Note? {
        guard var note = store.note(id) else { return nil }
        for p in [ephemeralPane, slotPane] {
            if let edited = p?.editor.note, edited.id == id { note.content = edited.content; note.links = edited.links }
        }
        return note
    }

    private func isLockedOut(_ note: Note) -> Bool {
        note.isLocked && !relock.isUnlocked(note.id, now: Date(), minutes: Defaults[.relockAfterMinutes])
    }

    /// Deletes the note `pane` is leaving when it is blank (slotted and locked notes are kept).
    private func leaveIfBlank(_ pane: NotePane, for newID: UUID?) {
        guard let old = pane.noteID, old != newID, let note = freshNote(old),
              note.slot == nil, !note.isLocked, DeckNavigator.isBlank(note.content) else { return }
        guard store.deleteIfEmpty(old) else { return }
        pane.clear()
        HUD.show("Empty note deleted")
    }

    private func showEphemeral(_ id: UUID) {
        leaveIfBlank(ephemeralPane, for: id)
        guard let note = store.note(id) else { return }
        ephemeralPane.show(note, locked: isLockedOut(note))
        Defaults[.shellKitCurrentNote] = id.uuidString
        Onboarding.noteShown(id)
        if !isSplit {
            openSlot = nil
            layoutPanes()
        }
        afterNavigation()
    }

    private func showFrontEphemeral() {
        if let front = ephemeralDeck().first { showEphemeral(front.id) } else { createNote() }
    }

    private func createNote() {
        let note = store.create(content: "")
        showEphemeral(note.id)
    }

    /// A swipe or ⌘[ / ⌘]: through the deck, or, while a slot is in front, through the slots holding a note.
    func navigate(_ direction: SwipeDirection) {
        if activeRole == .slot { navigateSlots(direction); return }
        let deck = ephemeralDeck()
        let index = deck.firstIndex { $0.id == ephemeralPane.noteID } ?? 0
        let blank = ephemeralPane.noteID.flatMap(freshNote).map { DeckNavigator.isBlank($0.content) } ?? true
        switch DeckNavigator.step(from: index, count: deck.count, direction: direction, currentIsEmpty: blank) {
        case .show(let i): showEphemeral(deck[i].id); slideIn(direction)
        case .createNew: createNote(); slideIn(direction); HUD.show("New note created")
        case .stay(let reason): if let reason { HUD.show(reason) }
        }
    }

    /// Next/Previous Slot: the neighbouring slot in use (from the deck, the first or the last one); at either end
    /// the note nudges back and a pill says so. Nothing is ever created here.
    func navigateSlots(_ direction: SwipeDirection) {
        let current = activeRole == .slot ? openSlot : nil
        switch SlotNavigator.step(from: current, occupied: Set(board().occupants.keys), direction: direction) {
        case .open(let slot)?: openSlot(slot, transition: direction)
        case .stay(let reason)?: bounce(direction); slotBar(.navigated); say(reason, at: current)
        case nil: HUD.show("No slots in use yet — Put in Slot gives this note one")
        }
    }

    /// The arriving note slides ~9 pt in from the side it came from while fading in (220 ms, ease-out); without a
    /// direction (a slot opened from the keyboard or the bar) it only fades in (150 ms). The page itself stays put.
    private func slideIn(_ direction: SwipeDirection?) {
        let view = pane(activeRole)
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let group = CAAnimationGroup()
        group.animations = [fade]
        group.duration = direction == nil ? 0.15 : 0.22
        if let direction {
            let shift = CABasicAnimation(keyPath: "transform.translation.x")
            shift.fromValue = direction == .previous ? -9 : 9
            shift.toValue = 0
            group.animations?.append(shift)
        }
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(group, forKey: "slideIn")
    }

    /// The end of the slots: the note gives 6 pt the way the swipe went and settles back (200 ms).
    private func bounce(_ direction: SwipeDirection) {
        let view = pane(activeRole)
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let nudge = CAKeyframeAnimation(keyPath: "transform.translation.x")
        nudge.values = [0, direction == .previous ? 6 : -6, 0]
        nudge.keyTimes = [0, 0.4, 1]
        nudge.duration = 0.2
        nudge.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(nudge, forKey: "bounce")
    }

    private func startFreshIfInactive() {
        let last = Defaults[.shellKitLastHidden]
        guard InactivityPolicy.shouldStartFresh(lastHidden: last > 0 ? Date(timeIntervalSince1970: last) : nil,
                                                now: Date(), minutes: Defaults[.newNoteAfterMinutes]) else { return }
        if !isSplit { openSlot = nil; layoutPanes() }
        if let front = ephemeralDeck().first, DeckNavigator.isBlank(freshNote(front.id)?.content ?? "") {
            showEphemeral(front.id)
        } else {
            createNote()
        }
    }

    private func returnedAfterInactivity() {
        guard launched, window.isVisible else { return }
        startFreshIfInactive()
        checkRelock()
    }

    // MARK: - Slots

    /// Shows the note in `slot` in place of the deck (or in the slotted half of the split), with a short fade (or
    /// a slide when `transition` says where it came from) and, when `announce`, a "Slot 3 · <title>" pill. The
    /// deck note stays loaded in its own pane, caret and scroll position included, for Back to Notes.
    func openSlot(_ slot: Int, transition: SwipeDirection? = nil, announce: Bool = true) {
        guard let note = slotNote(slot) else {
            let put = ChromeTooltip.shortcut(action: #selector(assignSlotItem(_:)), tag: slot).map { " · \($0) puts this note there" } ?? ""
            slotBar(.navigated)
            say("Slot \(slot + 1) is empty" + put, at: slot)
            return
        }
        openSlot = slot
        slotPane.show(note, locked: isLockedOut(note))
        if !isSplit { layoutPanes() }
        focus(.slot)
        afterNavigation()
        slotBar(.navigated)
        slideIn(transition)
        if announce { say(SlotBarLayout.label(slot: slot, title: note.isLocked ? "Locked note" : note.title), at: slot) }
    }

    /// Back to Notes: the deck note exactly as it was left. In the split, it just moves the focus over.
    private func showDeck() {
        if isSplit { focus(.ephemeral); return }
        guard openSlot != nil else { focusActive(); return }
        openSlot = nil
        layoutPanes()
        slotBar(.navigated)
        if ephemeralPane.noteID == nil { showFrontEphemeral() } else { afterNavigation() }
        slideIn(nil)
    }

    /// Esc goes back to the deck only when it means nothing to the note: a slot in front (not the split), the
    /// note's own text focused (not a field editor), Vim off (Esc leaves Insert there) and no editor list open
    /// over the note (those are child windows that take the mouse; the message pill doesn't).
    private var escapeGoesBack: Bool {
        guard !isSplit, openSlot != nil, !Defaults[.vimMode], let text = window.firstResponder as? NSTextView,
              !text.isFieldEditor, slotPane.contains(responder: text) else { return false }
        return !(window.childWindows ?? []).contains { $0.isVisible && !$0.ignoresMouseEvents }
    }

    /// A word about a slot: above its planet on the bar when there is one to point at (the bar is up after any
    /// slot move), as a message pill otherwise.
    private func say(_ text: String, at slot: Int?) {
        if let slot, slotsBar.isShown { slotsBar.announce(text, at: slot) } else { HUD.show(text) }
    }

    /// Shows `id` where it lives — its slot, or its place in the deck — putting `caret` back.
    private func reveal(_ id: UUID, caret: NSRange? = nil, announce: Bool = true) {
        guard let note = store.note(id) else { return }
        if let slot = note.slot {
            refillDeckPane()
            openSlot(slot, announce: announce)
            if let caret { slotPane.selection = caret }
        } else {
            showEphemeral(id)
            if let caret { ephemeralPane.selection = caret }
            slideIn(nil)
        }
    }

    /// Keeps the deck pane holding a note (the front one) without bringing the deck in front.
    private func refillDeckPane() {
        guard ephemeralPane.noteID == nil else { return }
        let front = ephemeralDeck().first ?? store.create(content: "")
        ephemeralPane.show(front, locked: isLockedOut(front))
        Defaults[.shellKitCurrentNote] = front.id.uuidString
    }

    /// A planet click opens its slot (the open one goes back to the deck); an empty slot takes the current note.
    private func slotChipClicked(_ slot: Int) {
        if activeRole == .slot, openSlot == slot, !isSplit { showDeck(); return }
        if slotNote(slot) != nil { openSlot(slot) } else { assign(toSlot: slot) }
    }

    /// The planet's right-click menu.
    private func slotMenu(_ slot: Int) -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = slot
        }
        let name = "Slot \(slot + 1)"
        if let note = slotNote(slot) {
            if activeRole == .slot, openSlot == slot, !isSplit {
                add("Back to Notes", #selector(goToDeck(_:)))
            } else {
                add("Open \(name)", #selector(openSlotItem(_:)))
            }
            if note.id != currentNoteID { add("Put This Note in \(name)", #selector(assignSlotItem(_:))) }
            menu.addItem(.separator())
            add("Remove “\(SlotBarLayout.cleanTitle(note.title))” from \(name)", #selector(clearSlotItem(_:)))
        } else {
            add("Put This Note in \(name)", #selector(assignSlotItem(_:)))
        }
        return menu
    }

    /// Put in Slot: the current note takes `slot`; a note already there goes back to the deck, and ⌘Z puts both
    /// back. The note keeps its caret when it changes panes.
    func assign(toSlot slot: Int) {
        guard let id = currentNoteID, SlotBoard.isValid(slot) else { return }
        if store.note(id)?.slot == slot { slotBar(.navigated); say("Already in slot \(slot + 1)", at: slot); return }
        let replaced = slotNote(slot)
        var b = board()
        guard moveSlots(id, changes: b.assign(id, to: slot)) else { return }
        if let replaced {
            say("In slot \(slot + 1) · ⌘Z puts “\(SlotBarLayout.cleanTitle(replaced.title))” back", at: slot)
        } else {
            say("In slot \(slot + 1)", at: slot)
        }
    }

    /// Remove from Slot: the note goes back to the deck (nothing is lost; ⌘Z puts it back in its slot).
    func removeFromSlot(id: UUID) {
        guard let slot = store.note(id)?.slot else { return }
        var b = board()
        guard moveSlots(id, changes: b.remove(id)) else { return }
        say("Back in your notes · ⌘Z undoes", at: slot)
    }

    /// Applies `changes` (`SlotBoard`'s) and shows `id` where it now lives, caret kept; ⌘Z puts everything back
    /// until the next edit or move. False when there was nothing to do.
    private func moveSlots(_ id: UUID, changes: [(id: UUID, slot: Int?)]) -> Bool {
        guard !changes.isEmpty else { HUD.show("Slot not available", kind: .warning); return false }
        let before = changes.map { (id: $0.id, slot: store.note($0.id)?.slot) }
        let caret = pane(activeRole).noteID == id ? pane(activeRole).selection : nil
        setSlots(changes)
        reveal(id, caret: caret, announce: false)
        offerUndo("Move to Slot") { shell in
            shell.setSlots(before)
            shell.reveal(id, caret: caret, announce: false)
            shell.say("Slots put back", at: shell.shownSlot)
        }
        return true
    }

    /// Writes slot changes to the store; panes holding a note whose place changed let go of it, and a split
    /// with no slots left closes.
    private func setSlots(_ changes: [(id: UUID, slot: Int?)]) {
        flushEditors()
        // Notes leaving a slot first, so a note moving in never shares it.
        for change in changes.sorted(by: { $0.slot == nil && $1.slot != nil }) { store.setSlot(change.slot, for: change.id) }
        if let id = slotPane.noteID, let s = store.note(id)?.slot {
            if openSlot != nil { openSlot = s }   // the slot pane follows its note to the new slot
        } else if slotPane.noteID != nil {
            slotPane.clear()
            openSlot = nil
        }
        if let id = ephemeralPane.noteID, store.note(id)?.slot != nil { ephemeralPane.clear() }
        if isSplit, board().isEmpty { Defaults[.shellKitSplit] = false }
        // The split's slotted half never goes empty: it falls back to the first slot in use.
        if isSplit, openSlot == nil, let first = board().occupants.keys.min(), let note = slotNote(first) {
            openSlot = first
            slotPane.show(note, locked: isLockedOut(note))
        }
    }

    // MARK: - Preview and self-test hooks (`WindowPreview`)

    var isSlotBarShown: Bool { slotsBar?.isShown ?? false }
    var shownSlot: Int? { activeRole == .slot ? openSlot : nil }
    var escapeMeansBack: Bool { escapeGoesBack }

    /// Starts over on the notes now in the store, as a fresh launch would, without rebuilding the window.
    func reloadForPreview() {
        guard launched else { return }
        ephemeralPane.clear()
        slotPane.clear()
        openSlot = nil
        noteUndo.removeAllActions()
        slotBarState = SlotBarVisibility(alwaysShow: Defaults[.alwaysShowSlotsBar])
        restoreCurrentNote()
        layoutPanes()
    }

    // MARK: - Slot bar

    private func slotBar(_ event: SlotBarVisibility.Event) {
        slotBarState.handle(event, at: Date())
        applySlotBarVisibility()
    }

    /// Shows or hides the bar as the rules say now, and comes back when time alone would change that.
    private func applySlotBarVisibility() {
        guard slotsBar != nil else { return }
        let now = Date()
        slotsBar.isShown = !bottomStripTaken && slotBarState.isVisible(at: now)
        slotBarWork?.cancel()
        slotBarWork = nil
        guard let next = slotBarState.nextChange(after: now) else { return }
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.applySlotBarVisibility() } }
        slotBarWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(next.timeIntervalSince(now), 0.01), execute: work)
    }

    /// The pointer over the window (`point` in the content view, nil when it left): in the strip along the
    /// bottom, on the revealed bottom bar or on the shown slot bar counts as the bar's zone. After a keystroke the
    /// pointer must really move before it counts again, so a hand resting on the trackpad never flickers the bar.
    private func pointerMoved(to point: NSPoint?) {
        guard let point else { slotBar(.pointer(inZone: false)); return }
        if let rest = pointerRest {
            if hypot(point.x - rest.x, point.y - rest.y) < 4 { return }
            pointerRest = nil
        }
        let strip = max(SlotBarVisibility.hoverZone, bottomBar.isRevealed ? Double(BottomBarView.height) : 0)
        let inZone = Double(point.y) <= strip || (slotsBar.isShown && slotsBar.frame.contains(point))
        slotBar(.pointer(inZone: inZone))
    }

    // MARK: - Split view

    private func splitChanged() {
        if isSplit, openSlot == nil {
            guard let first = board().occupants.keys.min() else {
                Defaults[.shellKitSplit] = false
                HUD.show("No slotted notes yet")
                return
            }
            openSlot(first)
        }
        layoutPanes()
        refreshChrome()
    }

    /// Puts the right pane(s) in the window: the deck pane, the slot pane, or the split. A pane already in place
    /// stays put (its caret and scroll position with it).
    private func layoutPanes() {
        guard ephemeralPane != nil else { return }
        if !isSplit, paneContainer.subviews.first === (openSlot != nil ? slotPane : ephemeralPane) { refreshChrome(); return }
        paneContainer.subviews.forEach { $0.removeFromSuperview() }
        let content: NSView
        if isSplit && openSlot != nil {
            let split = NSSplitView()
            split.isVertical = !Defaults[.shellKitSplitHorizontal]
            split.dividerStyle = .thin
            let panes = Defaults[.shellKitSwapPanes] ? [slotPane!, ephemeralPane!] : [ephemeralPane!, slotPane!]
            for p in panes {
                p.translatesAutoresizingMaskIntoConstraints = true
                split.addArrangedSubview(p)
            }
            content = split
        } else {
            content = openSlot != nil ? slotPane : ephemeralPane
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        paneContainer.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: paneContainer.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: paneContainer.trailingAnchor),
            content.topAnchor.constraint(equalTo: paneContainer.topAnchor),
            content.bottomAnchor.constraint(equalTo: paneContainer.bottomAnchor),
        ])
        if let split = content as? NSSplitView {
            paneContainer.layoutSubtreeIfNeeded()
            let length = split.isVertical ? split.bounds.width : split.bounds.height
            split.setPosition(length / 2, ofDividerAt: 0)
        }
        refreshChrome()
    }

    // MARK: - Chrome

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.refreshScheduled = false
                self?.validateVisibleNotes()
            }
        }
    }

    /// Reacts to store changes made elsewhere (palette, Void, URL scheme, sync).
    private func validateVisibleNotes() {
        guard launched else { return }
        let deckIDs = Set(ephemeralDeck().map(\.id))
        if let id = ephemeralPane.noteID, !deckIDs.contains(id) {
            ephemeralPane.clear()
            showFrontEphemeral()
        } else if ephemeralPane.noteID == nil {
            showFrontEphemeral()
        }
        if let slot = openSlot {
            if let note = slotNote(slot) {
                slotPane.show(note, locked: isLockedOut(note))
            } else if let id = slotPane.noteID, let moved = store.note(id)?.slot {
                openSlot = moved
            } else {
                slotPane.clear()
                openSlot = nil
                if isSplit { Defaults[.shellKitSplit] = false }
                layoutPanes()
            }
        }
        refreshChrome()
    }

    /// Editing or moving on leaves the deleted note in The Void (never while that undo is running).
    private func forgetUndoDelete() {
        if !noteUndo.isUndoing { noteUndo.removeAllActions() }
    }

    private func afterNavigation() {
        forgetUndoDelete()
        if presented != nil { present(inWindow: nil) }
        relock.setFocused(isFocusedOnUnlockedLockedNote, at: Date())
        applyThemeIfNeeded()
        refreshChrome()
        focusActive()
        scheduleAutoUnlock()
    }

    /// "Ask to unlock automatically": once a locked note has stayed in front for the set delay, Touch ID comes up
    /// by itself. Moving on cancels it; a cancelled prompt waits for the next visit.
    private func scheduleAutoUnlock() {
        autoUnlockWork?.cancel()
        autoUnlockWork = nil
        let delay = Defaults[.autoUnlockDelay], role = activeRole
        guard delay >= 0, window.isVisible, pane(role).isShowingLock, let id = pane(role).noteID else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.window.isKeyWindow, self.activeRole == role, self.pane(role).isShowingLock,
                      self.pane(role).noteID == id else { return }
                self.requestUnlock(role)
            }
        }
        autoUnlockWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func focusActive() { focus(activeRole) }

    /// Puts the caret in `role`'s note (when that pane is in the window and not behind its lock screen).
    private func focus(_ role: Role) {
        let p = pane(role)
        if p.window != nil, !p.isShowingLock { p.editor.focus() }
    }

    private func focusMoved() {
        relock.setFocused(isFocusedOnUnlockedLockedNote, at: Date())
        applyThemeIfNeeded()
        refreshChrome()
    }

    func refreshChrome() {
        guard let bottomBar else { return }
        let theme = chromeTheme
        let showBar = Defaults[.showBottomBar] && !bottomStripTaken
        if bottomBar.isHidden == showBar {
            bottomBar.isHidden = !showBar
            if !showBar { bottomBar.setRevealed(false, animated: false) }
        }
        var titles: [Int: String] = [:]
        for note in store.deck where note.slot != nil { titles[note.slot!] = note.isLocked ? "Locked note" : note.title }
        let role = activeRole
        slotsBar.update(titles: titles, open: role == .slot ? openSlot : nil, theme: theme)
        if slotBarState.alwaysShow != Defaults[.alwaysShowSlotsBar] { slotBarState.handle(.alwaysShow(Defaults[.alwaysShowSlotsBar]), at: Date()) }
        applySlotBarVisibility()
        slotsBarBottom.constant = bottomBar.isRevealed ? -BottomBarView.height : -SlotsBarView.bottomInset
        // An always-shown slot bar rests over the note: the end of a long note scrolls clear of it.
        let overlay = Defaults[.alwaysShowSlotsBar] ? SlotsBarView.height + SlotsBarView.bottomInset : 0
        for pane in [ephemeralPane, slotPane] { pane?.editor.bottomOverlay = overlay }

        let id = pane(role).noteID
        let note = id.flatMap { store.note($0) }
        var parts: [String] = []
        var latest = false
        if let note {
            if analyses[role]?.mode == .timer, let status = Services.timers?.status(noteID: note.id) {
                parts.append(status)
            } else {
                let formatter = Defaults[.showNoteDates] ? Self.dateTimeFormatter : Self.dateFormatter
                parts.append(formatter.string(from: Defaults[.showCreationDate] ? note.created : note.modified))
            }
        }
        if role == .slot, let slot = openSlot {
            parts.append(Planet(rawValue: slot)?.name ?? "Slot \(slot + 1)")
        } else {
            let deck = ephemeralDeck()
            if let i = deck.firstIndex(where: { $0.id == id }) {
                if Defaults[.showNoteCount] { parts.append("\(i + 1) of \(deck.count)") }
                latest = i == 0
            }
        }
        if pane(role).isShowingLock { parts.append("Locked") } else if note?.isReadOnly == true { parts.append("Read-only") }
        bottomBar.update(parts: parts, theme: theme)
        let quick = Defaults[.quickExportDestination]
        bottomBar.exportButton.refreshTooltip(label: quick.map { "Quick Export (\(ChromeText.shortName($0.displayName)))" } ?? "Export")
        latestDot.isHidden = !(latest && Defaults[.showLatestNoteIndicator]) || bottomBar.isRevealed || presented != nil
        latestDot.layer?.backgroundColor = NSColor(hex: theme.accent1Main).cgColor
        titleBar.setPinned(Defaults[.pinOnTop])
    }

    /// The latest-note dot: 5 pt in `accent1Main`, 16 pt in from the bottom-right corner.
    static let latestDotSize: CGFloat = 5
    static let latestDotInset: CGFloat = 16

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private func tick() {
        guard window.isVisible else { return }
        if analyses[activeRole]?.mode == .timer { refreshChrome() }
        checkRelock()
    }

    func pinStateChanged() { refreshChrome() }

    /// The chrome follows the note in front: slotted notes can have their own theme pair.
    private var chromeTheme: Theme { Theme.current(slotted: activeRole == .slot) }

    private func applyThemeIfNeeded() {
        if chromeTheme.id != appliedThemeID { applyTheme() }
    }

    private func applyTheme() {
        guard titleBar != nil else { return }
        let theme = chromeTheme
        appliedThemeID = theme.id
        let background = NSColor(hex: theme.background)
        var translucent = false
        if #available(macOS 15, *) { translucent = Defaults[.translucent] }
        window.isOpaque = !translucent
        window.backgroundColor = translucent ? .clear : background
        effectView.isHidden = !translucent
        let opacity = translucent ? CGFloat(min(max(Defaults[.translucencyOpacity], 0), 1)) : 1
        tintView.layer?.backgroundColor = background.withAlphaComponent(opacity).cgColor
        let backdrop: HoverBar.Backdrop = !translucent ? .none : Defaults[.solidBarsWhenTranslucent] ? .solid(background) : .material
        titleBar.setBackdrop(backdrop)
        bottomBar.setBackdrop(backdrop)
        titleBar.apply(theme: theme)
        window.alignTrafficLights()
        ephemeralPane.apply(theme: Theme.current(slotted: false))
        slotPane.apply(theme: Theme.current(slotted: true))
        refreshChrome()
    }

    // MARK: - Swipe

    /// Feeds trackpad scrolls to the swipe recogniser; true when the event belongs to a horizontal swipe.
    private func swallowsScroll(_ event: NSEvent) -> Bool {
        guard Defaults[.swipeNavigation], event.hasPreciseScrollingDeltas, isOverMainWindow(event) else { return false }
        let phase: SwipeAccumulator.Phase
        if !event.momentumPhase.isEmpty {
            phase = .momentum
        } else if event.phase.contains(.began) {
            phase = .began
        } else if event.phase.contains(.changed) {
            phase = .changed
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            phase = .ended
        } else {
            return false
        }
        swipe.sensitivity = Defaults[.swipeSensitivity]
        // Positive when the fingers move right/down, whatever the natural-scrolling setting.
        let sign: Double = event.isDirectionInvertedFromDevice ? 1 : -1
        switch swipe.feed(phase: phase, fingerDX: Double(event.scrollingDeltaX) * sign,
                          fingerDY: Double(event.scrollingDeltaY) * sign) {
        case .pass: return false
        case .consume: return true
        case .navigate(let direction): navigate(direction); return true
        }
    }

    /// Scrolls that target the note window. Some scroll events (e.g. from other input sources) carry no window,
    /// so fall back to "pointer is over the key note window".
    private func isOverMainWindow(_ event: NSEvent) -> Bool {
        if let w = event.window { return w === window }
        return window.isVisible && window.frame.contains(NSEvent.mouseLocation)
    }

    // MARK: - Locking

    private var isFocusedOnUnlockedLockedNote: Bool {
        guard window.isKeyWindow, let id = currentNoteID, let note = store.note(id) else { return false }
        return note.isLocked && relock.unlocked.contains(id)
    }

    private func checkRelock() {
        if relock.expireIfNeeded(now: Date(), minutes: Defaults[.relockAfterMinutes]) { rerenderPanes() }
    }

    @objc func relockNotes(_ sender: Any?) { relockAll() }

    func relockAll() {
        relock.relockAll()
        rerenderPanes()
        HUD.show("Locked notes are locked again")
    }

    private func rerenderPanes() {
        if let id = ephemeralPane.noteID, let note = store.note(id) { ephemeralPane.show(note, locked: isLockedOut(note)) }
        if let id = slotPane.noteID, let note = store.note(id) { slotPane.show(note, locked: isLockedOut(note)) }
        refreshChrome()
    }

    private func requestUnlock(_ role: Role) {
        guard let id = pane(role).noteID else { return }
        authenticate(reason: "show a locked note") { [weak self] in
            guard let self else { return }
            relock.unlock(id, at: Date())
            rerenderPanes()
            pane(role).editor.focus()
        }
    }

    private func authenticate(reason: String, then: @escaping @MainActor () -> Void) {
        guard !authInFlight else { return }
        authInFlight = true
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authInFlight = false
            Alerts.error("Touch ID or a password is needed to unlock notes.", error)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
            Task { @MainActor in
                Shell.shared.authInFlight = false
                if ok { then() }
            }
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideMain()
        return false
    }

    func windowDidResize(_ notification: Notification) { window.alignTrafficLights() }

    func windowDidBecomeKey(_ notification: Notification) {
        checkRelock()
        relock.setFocused(isFocusedOnUnlockedLockedNote, at: Date())
    }

    func windowDidResignKey(_ notification: Notification) {
        relock.setFocused(false, at: Date())
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.authInFlight, self.window.isVisible, !self.window.isKeyWindow,
                      Presence.shared.hidesOnFocusLoss else { return }
                // Our own windows (Settings, palette, alerts) keep the note window around.
                if NSApp.isActive && NSApp.keyWindow != nil { return }
                self.hideMain()
            }
        }
    }

    // MARK: - Menu actions

    @objc func newNote(_ sender: Any?) {
        if activeRole == .slot {
            guard Defaults[.shellKitNewNotesInEphemeral] else {
                HUD.show("New notes can only be created in the ephemeral pane", kind: .warning)
                return
            }
            if !isSplit { openSlot = nil; layoutPanes() }
        }
        if let front = ephemeralDeck().first, DeckNavigator.isBlank(freshNote(front.id)?.content ?? "") {
            showEphemeral(front.id)
        } else {
            createNote()
        }
        if !window.isVisible { showMain() }
        window.makeFirstResponder(ephemeralPane.editor.view)
        focusActive()
    }

    @objc func previousNote(_ sender: Any?) { navigate(.previous) }
    @objc func nextNote(_ sender: Any?) { navigate(.next) }

    @objc func goToFirstNote(_ sender: Any?) {
        if !isSplit && openSlot != nil { showDeck() }
        guard let front = ephemeralDeck().first else { return }
        if front.id == ephemeralPane.noteID { HUD.show("Already at the front") }
        showEphemeral(front.id)
    }

    @objc func goToDeck(_ sender: Any?) { showDeck() }
    /// Esc's hidden twin of Back to Notes; `validateMenuItem` lets it fire only when Esc is free.
    @objc func backToNotesEscape(_ sender: Any?) { showDeck() }
    @objc func previousSlot(_ sender: Any?) { navigateSlots(.previous) }
    @objc func nextSlot(_ sender: Any?) { navigateSlots(.next) }
    @objc func openSlotItem(_ sender: NSMenuItem) { openSlot(sender.tag) }
    @objc func assignSlotItem(_ sender: NSMenuItem) { assign(toSlot: sender.tag) }
    /// The planet menu's Remove: whichever note is in that slot goes back to the deck.
    @objc func clearSlotItem(_ sender: NSMenuItem) {
        guard let note = slotNote(sender.tag) else { return }
        removeFromSlot(id: note.id)
    }

    @objc func removeFromSlot(_ sender: Any?) {
        guard let id = currentNoteID else { return }
        removeFromSlot(id: id)
    }

    @objc func moveToVoid(_ sender: Any?) {
        guard let id = currentNoteID, let note = freshNote(id) else { return }
        if DeckNavigator.isBlank(note.content) && note.slot == nil {
            pane(activeRole).clear()
            store.deletePermanently(id)
        } else {
            guard Alerts.confirm("Delete this note?", info: "It moves to The Void, where it can be restored. ⌘Z undoes right away.",
                                 confirmTitle: "Delete", suppressionID: "shellKit.moveToVoid") else { return }
            store.moveToVoid(id)
            validateVisibleNotes()
            offerUndoDelete(id)
            HUD.show("Note deleted · ⌘Z to undo")
            return
        }
        validateVisibleNotes()
    }

    @objc func recoverFromVoid(_ sender: Any?) { Services.panels?.showVoid() }
    @objc func emptyVoid(_ sender: Any?) { Services.panels?.emptyVoid() }
    @objc func searchAllNotes(_ sender: Any?) { Services.panels?.showSearch() }
    @objc func showCommandPalette(_ sender: Any?) { Services.panels?.showCommandPalette() }

    @objc func exportItem(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let destination = ExportDestination(rawValue: raw) else { return }
        export(to: destination)
    }

    @objc func quickExport(_ sender: Any?) {
        guard let destination = Defaults[.quickExportDestination] else {
            HUD.show("Choose a Quick Export destination in Settings → Export")
            return
        }
        export(to: destination)
    }

    private func export(to destination: ExportDestination) {
        guard let id = currentNoteID, let note = freshNote(id) else { HUD.show("No note to export", kind: .warning); return }
        Services.export?.export(note, to: destination)
    }

    @objc func printNote(_ sender: Any?) {
        guard let id = currentNoteID, let note = freshNote(id), !isLockedOut(note) else {
            HUD.show("No note to print", kind: .warning); return
        }
        Services.export?.print(note)
    }

    @objc func editorCommand(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let command = EditorCommand(rawValue: raw) else { return }
        let p = pane(activeRole)
        guard !p.isShowingLock else { return }
        p.editor.perform(command)
    }

    @objc func promoteToFront(_ sender: Any?) {
        guard let id = currentNoteID, let note = store.note(id) else { return }
        if note.slot != nil { HUD.show("Slotted notes stay in their slot", kind: .warning); return }
        if ephemeralDeck().first?.id == id { HUD.show("Already at the front"); return }
        store.promoteToFront(id)
        HUD.show("Moved to the front")
    }

    @objc func toggleLock(_ sender: Any?) {
        guard let id = currentNoteID, var note = freshNote(id) else { return }
        if note.isLocked {
            authenticate(reason: "remove the lock from this note") { [weak self] in
                guard let self, var current = freshNote(id) else { return }
                current.isLocked = false
                store.update(current)
                rerenderPanes()
                HUD.show("Note unlocked")
            }
        } else {
            note.isLocked = true
            store.update(note)
            relock.lock(id)
            rerenderPanes()
            HUD.show("Note locked")
        }
    }

    @objc func toggleReadOnly(_ sender: Any?) {
        guard let id = currentNoteID, var note = freshNote(id) else { return }
        note.isReadOnly.toggle()
        store.update(note)
        let p = pane(activeRole)
        p.editor.load(note)
        HUD.show(note.isReadOnly ? "Note is now read-only" : "Note is editable again")
        refreshChrome()
    }

    @objc func archiveNote(_ sender: Any?) {
        guard let id = currentNoteID else { return }
        store.setArchived(true, for: id)
        HUD.show("Note archived")
        validateVisibleNotes()
    }

    /// The top bar's Typing button: its menu of typing switches, under the button.
    @objc func showTypingOptions(_ sender: Any?) {
        let anchor = (sender as? NSView) ?? titleBar.typingButton
        TypingMenu.show(mode: analyses[activeRole]?.mode ?? .plain, under: anchor, target: self,
                        action: #selector(toggleTypingOption(_:)))
    }

    @objc func toggleTypingOption(_ sender: NSMenuItem) {
        guard TypingOption.allCases.indices.contains(sender.tag) else { return }
        let option = TypingOption.allCases[sender.tag]
        option.isOn.toggle()
        let mode = analyses[activeRole]?.mode ?? .plain
        let state = option.isOn ? "on" : "off"
        HUD.show(option.isSuspended(in: mode) && option.isOn ? "\(option.title) \(state) · not in \(mode.displayName.lowercased()) notes"
                                                           : "\(option.title) \(state)")
    }

    @objc func togglePin(_ sender: Any?) {
        Defaults[.pinOnTop].toggle()
        HUD.show(Defaults[.pinOnTop] ? "Pinned on top" : "Unpinned")
    }

    @objc func toggleSlotsBar(_ sender: Any?) { Defaults[.alwaysShowSlotsBar].toggle() }
    @objc func toggleSplit(_ sender: Any?) { Defaults[.shellKitSplit].toggle() }
    @objc func toggleSplitHorizontal(_ sender: Any?) { Defaults[.shellKitSplitHorizontal].toggle() }
    @objc func swapPanes(_ sender: Any?) { Defaults[.shellKitSwapPanes].toggle() }
    @objc func openSettings(_ sender: Any?) { showSettings(tab: nil) }
    @objc func openShortcutsSettings(_ sender: Any?) { showSettings(tab: SettingsTab.shortcuts.rawValue) }
    @objc func showMainWindow(_ sender: Any?) { showMain() }

    @objc func showTutorial(_ sender: Any?) {
        Onboarding.seedTutorial()
        showFrontEphemeral()
        showMain()
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: NSAttributedString(string: "A scratchpad for macOS. MIT License.")])
        NSApp.activate()
    }

    /// The bottom bar's Export button: Quick Export when a destination is chosen; otherwise a menu of the enabled
    /// destinations and Print.
    @objc func exportFromBar(_ sender: NSView) {
        if Defaults[.quickExportDestination] != nil { quickExport(sender); return }
        let menu = MainMenu.exportMenu(target: self)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Print...", action: #selector(printNote(_:)), keyEquivalent: "").target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    // MARK: - Validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let note = currentNoteID.flatMap { Services.store?.note($0) }
        switch item.action {
        case #selector(toggleSlotsBar(_:)): item.state = Defaults[.alwaysShowSlotsBar] ? .on : .off
        case #selector(toggleTypingOption(_:)): return true
        case #selector(toggleSplitHorizontal(_:)): item.state = Defaults[.shellKitSplitHorizontal] ? .on : .off; return isSplit
        case #selector(swapPanes(_:)): return isSplit
        case #selector(toggleLock(_:)), #selector(toggleReadOnly(_:)): return note != nil   // MenuState sets their titles
        case #selector(relockNotes(_:)): return !relock.unlocked.isEmpty
        case #selector(removeFromSlot(_:)): return note?.slot != nil
        case #selector(clearSlotItem(_:)): return slotNote(item.tag) != nil
        case #selector(assignSlotItem(_:)): item.state = note?.slot == item.tag ? .on : .off; return note != nil
        case #selector(openSlotItem(_:)): item.state = activeRole == .slot && openSlot == item.tag ? .on : .off
        case #selector(goToDeck(_:)): item.state = activeRole == .ephemeral ? .on : .off
        case #selector(backToNotesEscape(_:)): return escapeGoesBack
        case #selector(previousSlot(_:)), #selector(nextSlot(_:)): return !board().isEmpty
        case #selector(editorCommand(_:)): return note != nil && !pane(activeRole).isShowingLock
        case #selector(moveToVoid(_:)), #selector(archiveNote(_:)), #selector(printNote(_:)),
             #selector(promoteToFront(_:)), #selector(quickExport(_:)), #selector(exportItem(_:)):
            return note != nil
        default: break
        }
        return true
    }

    /// Keeps the Export submenu in sync with the enabled destinations.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in MainMenu.exportMenu(target: self, forMainMenu: true).items { item.menu?.removeItem(item); menu.addItem(item) }
    }
}
