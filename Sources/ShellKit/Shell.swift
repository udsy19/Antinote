import AppKit
import Combine
import LocalAuthentication
import JotterCore

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
    private var slotsBarHeight: NSLayoutConstraint!
    private var bottomBar: BottomBarView!
    private let paneContainer = NSView()
    private let effectView = NSVisualEffectView()
    private let tintView = NSView()

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

    private var store: NoteStoring { Services.store }
    private var isSplit: Bool { Defaults[.shellKitSplit] }

    // MARK: - Launch

    func launch() {
        guard !launched else { return }
        launched = true
        buildWindow()
        Onboarding.runIfNeeded()
        restoreCurrentNote()
        observe()
        Presence.shared.start()
        AppIcons.apply()
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleReopen(_:reply:)),
                                                     forEventClass: AEEventClass(kCoreEventClass),
                                                     andEventID: AEEventID(kAEReopenApplication))
        if !Presence.shared.isDropdown { showMain() }
    }

    @objc private func handleReopen(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) { showMain() }

    private func buildWindow() {
        let root = NSView()
        titleBar = TitleBarView(target: self)
        titleBar.onHoverChange = { [weak self] revealed in
            self?.window.trafficLights.forEach { $0.animator().alphaValue = revealed ? 1 : 0 }
        }
        slotsBar = SlotsBarView()
        slotsBar.onSelect = { [weak self] slot in self?.slotChipClicked(slot) }
        bottomBar = BottomBarView(target: self)
        effectView.material = .underWindowBackground
        effectView.blendingMode = .behindWindow
        effectView.state = .followsWindowActiveState
        tintView.wantsLayer = true

        for v in [effectView, tintView, titleBar, slotsBar, paneContainer, bottomBar] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        slotsBarHeight = slotsBar.heightAnchor.constraint(equalToConstant: 0)
        var constraints: [NSLayoutConstraint] = []
        for v in [effectView, tintView] {
            constraints += [v.leadingAnchor.constraint(equalTo: root.leadingAnchor), v.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                            v.topAnchor.constraint(equalTo: root.topAnchor), v.bottomAnchor.constraint(equalTo: root.bottomAnchor)]
        }
        for v in [titleBar, slotsBar, paneContainer, bottomBar] as [NSView] {
            constraints += [v.leadingAnchor.constraint(equalTo: root.leadingAnchor), v.trailingAnchor.constraint(equalTo: root.trailingAnchor)]
        }
        constraints += [
            titleBar.topAnchor.constraint(equalTo: root.topAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: TitleBarView.height),
            slotsBar.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            slotsBarHeight,
            paneContainer.topAnchor.constraint(equalTo: slotsBar.bottomAnchor),
            paneContainer.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: BottomBarView.height),
            bottomBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ]
        NSLayoutConstraint.activate(constraints)
        window.contentView = root
        window.delegate = self
        window.trafficLights.forEach { $0.alphaValue = 0 }

        ephemeralPane = makePane(.ephemeral)
        slotPane = makePane(.slot)
        if !window.setFrameUsingName("JotterMainWindow") { window.center() }
        layoutPanes()
        applyTheme()
    }

    private func makePane(_ role: Role) -> NotePane {
        let editor = Services.editorFactory.makeEditor()
        let pane = NotePane(editor: editor) { [weak self] in self?.requestUnlock(role) }
        editor.onAnalysis = { [weak self] analysis in
            self?.analyses[role] = analysis
            self?.refreshChrome()
        }
        return pane
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
        Defaults.changes
            .filter { ["lightTheme", "darkTheme", "translucent"].contains($0) }
            .sink { [weak self] _ in self?.applyTheme() }.store(in: &cancellables)
        Defaults.changes
            .filter { ["showLatestNoteIndicator", "showNoteDates", "alwaysShowSlotsBar"].contains($0) }
            .sink { [weak self] _ in self?.refreshChrome() }.store(in: &cancellables)
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
        timers.append(Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        })
    }

    private func restoreCurrentNote() {
        let deck = ephemeralDeck()
        if let id = UUID(uuidString: Defaults[.shellKitCurrentNote]), deck.contains(where: { $0.id == id }) {
            showEphemeral(id)
        } else if let front = deck.first {
            showEphemeral(front.id)
        } else {
            createNote()
        }
    }

    // MARK: - WindowServicing

    var currentNoteID: UUID? { pane(activeRole).noteID }

    func showMain() {
        if !window.isVisible { startFreshIfInactive() }
        checkRelock()
        Presence.shared.positionDropdown(window)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        focusActive()
    }

    func toggleMain() {
        if window.isVisible && window.isKeyWindow && NSApp.isActive { hideMain() } else { showMain() }
    }

    func show(noteID: UUID) {
        guard let note = store.note(noteID) else { return }
        if let slot = note.slot { openSlot(slot) } else { showEphemeral(noteID) }
        showMain()
    }

    func showSettings(tab: String?) {
        SettingsWindow.shared.show(tab: SettingsTab(routing: tab))
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

    /// Non-slotted notes, front first.
    private func ephemeralDeck() -> [Note] { store.deck.filter { $0.slot == nil } }
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
        HUD.show("Empty note deleted", symbol: "trash")
    }

    private func showEphemeral(_ id: UUID) {
        leaveIfBlank(ephemeralPane, for: id)
        guard let note = store.note(id) else { return }
        ephemeralPane.show(note, locked: isLockedOut(note))
        Defaults[.shellKitCurrentNote] = id.uuidString
        if !isSplit, openSlot != nil {
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

    func navigate(_ direction: SwipeDirection) {
        if !isSplit, let current = openSlot {
            let used = board().occupants.keys.sorted()
            guard let i = used.firstIndex(of: current) else { return }
            let j = direction == .previous ? i - 1 : i + 1
            if used.indices.contains(j) { openSlot(used[j]) } else { HUD.show("No more slotted notes", symbol: "square.grid.3x3") }
            return
        }
        let deck = ephemeralDeck()
        let index = deck.firstIndex { $0.id == ephemeralPane.noteID } ?? 0
        let blank = ephemeralPane.noteID.flatMap(freshNote).map { DeckNavigator.isBlank($0.content) } ?? true
        switch DeckNavigator.step(from: index, count: deck.count, direction: direction, currentIsEmpty: blank) {
        case .show(let i): showEphemeral(deck[i].id)
        case .createNew: createNote(); HUD.show("New note created", symbol: "square.and.pencil")
        case .stay(let reason): if let reason { HUD.show(reason, symbol: "arrow.left.and.right") }
        }
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

    func openSlot(_ slot: Int) {
        guard let note = slotNote(slot) else {
            HUD.show("Slot \(slot + 1) is empty — ⌃⌘\(slot + 1) puts this note there", symbol: "square.dashed")
            return
        }
        let wasOpen = openSlot != nil
        openSlot = slot
        slotPane.show(note, locked: isLockedOut(note))
        if !isSplit && !wasOpen { layoutPanes() }
        afterNavigation()
        if !isSplit || slotPane.window != nil { window.makeFirstResponder(slotPane.editor.view) }
        focusActive()
    }

    private func showDeck() {
        guard openSlot != nil, !isSplit else { focusActive(); return }
        openSlot = nil
        layoutPanes()
        if ephemeralPane.noteID == nil { showFrontEphemeral() } else { afterNavigation() }
    }

    private func slotChipClicked(_ slot: Int?) {
        guard let slot else { showDeck(); return }
        if slotNote(slot) != nil { openSlot(slot) } else { assign(toSlot: slot) }
    }

    func assign(toSlot slot: Int) {
        guard let id = currentNoteID else { return }
        var b = board()
        let changes = b.assign(id, to: slot)
        guard !changes.isEmpty else { HUD.show("Slot not available", symbol: "xmark.circle"); return }
        for change in changes { store.setSlot(change.slot, for: change.id) }
        guard let note = store.note(id) else { return }
        if let s = note.slot {
            openSlot = s
            slotPane.show(note, locked: isLockedOut(note))
            if ephemeralPane.noteID == id { ephemeralPane.clear(); showFrontEphemeral() }
            if !isSplit { openSlot = s; layoutPanes() }
            HUD.show("Moved to slot \(s + 1)", symbol: "square.grid.3x3.fill")
        } else {
            if slotPane.noteID == id { slotPane.clear(); openSlot = nil }
            if isSplit && b.isEmpty { Defaults[.shellKitSplit] = false }
            showEphemeral(id)
            layoutPanes()
            HUD.show("Removed from slot", symbol: "square.dashed")
        }
        afterNavigation()
    }

    // MARK: - Split view

    private func splitChanged() {
        if isSplit, openSlot == nil {
            guard let first = board().occupants.keys.min() else {
                Defaults[.shellKitSplit] = false
                HUD.show("No slotted notes yet", symbol: "square.dashed")
                return
            }
            openSlot(first)
        }
        layoutPanes()
        refreshChrome()
    }

    private func layoutPanes() {
        guard ephemeralPane != nil else { return }
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

    private func afterNavigation() {
        relock.setFocused(isFocusedOnUnlockedLockedNote, at: Date())
        refreshChrome()
        focusActive()
    }

    private func focusActive() {
        let p = pane(activeRole)
        if !p.isShowingLock { p.editor.focus() }
    }

    private func focusMoved() {
        relock.setFocused(isFocusedOnUnlockedLockedNote, at: Date())
        refreshChrome()
    }

    func refreshChrome() {
        guard let bottomBar else { return }
        let theme = Theme.current
        let b = board()
        var titles: [Int: String] = [:]
        for note in store.deck where note.slot != nil { titles[note.slot!] = note.isLocked ? "Locked note" : note.title }
        let showBar = Defaults[.alwaysShowSlotsBar] || !b.isEmpty || openSlot != nil
        slotsBar.isHidden = !showBar
        slotsBarHeight.constant = showBar ? SlotsBarView.height : 0
        slotsBar.update(titles: titles, open: activeRole == .slot ? openSlot : nil, theme: theme)

        let role = activeRole
        let id = pane(role).noteID
        let note = id.flatMap { store.note($0) }
        var position = ""
        var latest = false
        if role == .slot, let slot = openSlot {
            position = "Slot \(slot + 1)"
        } else {
            let deck = ephemeralDeck()
            if let i = deck.firstIndex(where: { $0.id == id }) {
                position = "\(i + 1) / \(deck.count)"
                latest = i == 0
            }
        }
        if Defaults[.showNoteDates], let note { position = Self.dateFormatter.string(from: note.modified) + "  ·  " + position }
        bottomBar.update(summary: summaryText(note: note, role: role), position: position, latest: latest, theme: theme)
        titleBar.setPinned(Defaults[.pinOnTop])
    }

    private func summaryText(note: Note?, role: Role) -> String {
        guard let note else { return "" }
        if pane(role).isShowingLock { return "Locked" }
        var parts: [String] = []
        if let analysis = analyses[role] {
            if analysis.mode == .timer, let status = Services.timers?.status(noteID: note.id) {
                parts.append(status)
            } else if let summary = analysis.summary {
                parts.append(summary)
            } else if analysis.mode != .plain {
                parts.append(analysis.mode.displayName)
            }
        }
        if note.isReadOnly { parts.append("Read-only") }
        return parts.joined(separator: "  ·  ")
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    private func tick() {
        guard window.isVisible else { return }
        if analyses[activeRole]?.mode == .timer { refreshChrome() }
        checkRelock()
    }

    func pinStateChanged() { refreshChrome() }

    private func applyTheme() {
        guard titleBar != nil else { return }
        let theme = Theme.current
        let background = NSColor(hex: theme.background)
        var translucent = false
        if #available(macOS 15, *) { translucent = Defaults[.translucent] }
        window.isOpaque = !translucent
        window.backgroundColor = translucent ? .clear : background
        effectView.isHidden = !translucent
        tintView.layer?.backgroundColor = background.withAlphaComponent(translucent ? 0.55 : 1).cgColor
        titleBar.apply(theme: theme)
        ephemeralPane.apply(theme: theme)
        slotPane.apply(theme: theme)
        refreshChrome()
    }

    // MARK: - Swipe

    /// Feeds trackpad scrolls to the swipe recogniser; true when the event belongs to a horizontal swipe.
    private func swallowsScroll(_ event: NSEvent) -> Bool {
        guard event.window === window, Defaults[.swipeNavigation], event.hasPreciseScrollingDeltas else { return false }
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

    // MARK: - Locking

    private var isFocusedOnUnlockedLockedNote: Bool {
        guard window.isKeyWindow, let id = currentNoteID, let note = store.note(id) else { return false }
        return note.isLocked && relock.unlocked.contains(id)
    }

    private func checkRelock() {
        if relock.expireIfNeeded(now: Date(), minutes: Defaults[.relockAfterMinutes]) { rerenderPanes() }
    }

    func relockAll() {
        relock.relockAll()
        rerenderPanes()
        HUD.show("Locked notes are locked again", symbol: "lock.fill")
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
                HUD.show("New notes can only be created in the ephemeral pane", symbol: "exclamationmark.circle")
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
        if front.id == ephemeralPane.noteID { HUD.show("Note is already first", symbol: "arrow.right.to.line") }
        showEphemeral(front.id)
    }

    @objc func goToDeck(_ sender: Any?) { showDeck() }
    @objc func openSlotItem(_ sender: NSMenuItem) { openSlot(sender.tag) }
    @objc func assignSlotItem(_ sender: NSMenuItem) { assign(toSlot: sender.tag) }

    @objc func removeFromSlot(_ sender: Any?) {
        guard let id = currentNoteID, let slot = store.note(id)?.slot else { return }
        assign(toSlot: slot)
    }

    @objc func moveToVoid(_ sender: Any?) {
        guard let id = currentNoteID, let note = freshNote(id) else { return }
        if DeckNavigator.isBlank(note.content) && note.slot == nil {
            pane(activeRole).clear()
            store.deletePermanently(id)
        } else {
            guard Alerts.confirm("Move this note to The Void?",
                                 info: "You can recover it from File → Recover from The Void… until The Void is emptied.",
                                 confirmTitle: "Move to The Void", suppressionID: "shellKit.moveToVoid") else { return }
            store.moveToVoid(id)
            HUD.show("Note banished to The Void", symbol: "trash")
        }
        validateVisibleNotes()
    }

    @objc func recoverFromVoid(_ sender: Any?) { Services.panels?.showVoid() }
    @objc func searchAllNotes(_ sender: Any?) { Services.panels?.showSearch() }
    @objc func showCommandPalette(_ sender: Any?) { Services.panels?.showCommandPalette() }

    @objc func exportItem(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let destination = ExportDestination(rawValue: raw) else { return }
        export(to: destination)
    }

    @objc func quickExport(_ sender: Any?) {
        guard let destination = Defaults[.quickExportDestination] else {
            HUD.show("Choose a Quick Export destination in Settings → Export", symbol: "square.and.arrow.up")
            return
        }
        export(to: destination)
    }

    private func export(to destination: ExportDestination) {
        guard let id = currentNoteID, let note = freshNote(id) else { HUD.show("No note to export", symbol: "xmark.circle"); return }
        Services.export?.export(note, to: destination)
    }

    @objc func printNote(_ sender: Any?) {
        guard let id = currentNoteID, let note = freshNote(id), !isLockedOut(note) else {
            HUD.show("No note to print", symbol: "xmark.circle"); return
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
        if note.slot != nil { HUD.show("Slotted notes don't have a front position", symbol: "exclamationmark.circle"); return }
        if ephemeralDeck().first?.id == id { HUD.show("Note is already first", symbol: "arrow.right.to.line"); return }
        store.promoteToFront(id)
        HUD.show("Promoted note to front", symbol: "arrow.up.to.line")
    }

    @objc func toggleLock(_ sender: Any?) {
        guard let id = currentNoteID, var note = freshNote(id) else { return }
        if note.isLocked {
            authenticate(reason: "remove the lock from this note") { [weak self] in
                guard let self, var current = freshNote(id) else { return }
                current.isLocked = false
                store.update(current)
                rerenderPanes()
                HUD.show("Note unlocked", symbol: "lock.open")
            }
        } else {
            note.isLocked = true
            store.update(note)
            relock.lock(id)
            rerenderPanes()
            HUD.show("Note locked", symbol: "lock.fill")
        }
    }

    @objc func toggleReadOnly(_ sender: Any?) {
        guard let id = currentNoteID, var note = freshNote(id) else { return }
        note.isReadOnly.toggle()
        store.update(note)
        let p = pane(activeRole)
        p.editor.load(note)
        HUD.show(note.isReadOnly ? "Note is now read-only" : "Note is editable again",
                 symbol: note.isReadOnly ? "lock.doc" : "pencil")
        refreshChrome()
    }

    @objc func archiveNote(_ sender: Any?) {
        guard let id = currentNoteID else { return }
        store.setArchived(true, for: id)
        HUD.show("Note archived", symbol: "archivebox")
        validateVisibleNotes()
    }

    @objc func togglePin(_ sender: Any?) {
        Defaults[.pinOnTop].toggle()
        HUD.show(Defaults[.pinOnTop] ? "Pinned on top" : "Unpinned from top", symbol: Defaults[.pinOnTop] ? "pin.fill" : "pin.slash")
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

    @objc func showMoreMenu(_ sender: NSButton) {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) { menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self }
        add("Search All Notes", #selector(searchAllNotes(_:)))
        add("Command Palette", #selector(showCommandPalette(_:)))
        add("Recover from The Void…", #selector(recoverFromVoid(_:)))
        menu.addItem(.separator())
        add("Promote to Front", #selector(promoteToFront(_:)))
        add("Lock Note", #selector(toggleLock(_:)))
        add("Read-Only", #selector(toggleReadOnly(_:)))
        add("Archive", #selector(archiveNote(_:)))
        add("Move to The Void", #selector(moveToVoid(_:)))
        menu.addItem(.separator())
        let export = NSMenuItem(title: "Export", action: nil, keyEquivalent: "")
        export.submenu = MainMenu.exportMenu(target: self)
        menu.addItem(export)
        add("Quick Export", #selector(quickExport(_:)))
        add("Print…", #selector(printNote(_:)))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    // MARK: - Validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let note = currentNoteID.flatMap { Services.store?.note($0) }
        switch item.action {
        case #selector(togglePin(_:)): item.state = Defaults[.pinOnTop] ? .on : .off
        case #selector(toggleSlotsBar(_:)): item.state = Defaults[.alwaysShowSlotsBar] ? .on : .off
        case #selector(toggleSplit(_:)): item.state = isSplit ? .on : .off
        case #selector(toggleSplitHorizontal(_:)): item.state = Defaults[.shellKitSplitHorizontal] ? .on : .off; return isSplit
        case #selector(swapPanes(_:)): return isSplit
        case #selector(toggleLock(_:)): item.title = note?.isLocked == true ? "Unlock Note…" : "Lock Note"; return note != nil
        case #selector(toggleReadOnly(_:)): item.state = note?.isReadOnly == true ? .on : .off; return note != nil
        case #selector(removeFromSlot(_:)): return note?.slot != nil
        case #selector(assignSlotItem(_:)): item.state = note?.slot == item.tag ? .on : .off; return note != nil
        case #selector(openSlotItem(_:)): item.state = activeRole == .slot && openSlot == item.tag ? .on : .off
        case #selector(goToDeck(_:)): item.state = activeRole == .ephemeral ? .on : .off
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
        for item in MainMenu.exportMenu(target: self).items { item.menu?.removeItem(item); menu.addItem(item) }
    }
}
