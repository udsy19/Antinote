import AppKit
import Combine
import JotterCore
import UserNotifications

extension Defaults.Keys {
    /// Timer state by note UUID string (survives relaunches).
    static let toolsKitTimers = Key<[String: TimerRun]>("toolsKit.timers", default: [:])
    /// Pomodoro breaks sat out without peeking.
    static let toolsKitNoPeekStreak = Key<NoPeekStreak>("toolsKit.noPeekStreak", default: NoPeekStreak())
}

public extension Notification.Name {
    /// Posted whenever a timer's display may have changed (every tick while running). `object` is the note's UUID.
    static let jotterTimersDidChange = Notification.Name("JotterTimersDidChange")
}

/// Runs the timers of `timer` notes: one per note, any number of notes at once.
@MainActor
public final class TimerManager: NSObject, TimerServicing {
    private var runs: [UUID: TimerRun] = [:]
    private let clock: () -> Date
    private var lastTick: Date
    private var ticker: Timer?
    private var cancellables: Set<AnyCancellable> = []

    public init(clock: @escaping () -> Date = Date.init) {
        self.clock = clock
        lastTick = clock()
        super.init()
        restore()
        Defaults.changes.filter { $0 == Defaults.Keys.timerInMenuBar.name }
            .sink { [weak self] _ in self?.refreshMenuBarText() }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.prepareForQuit() }
        }
        scheduleTicker()
    }

    // MARK: TimerServicing

    public func start(noteID: UUID, arguments: String) {
        let parsed = TimerSpec.parse(withNoteKeyword(noteID: noteID, arguments: arguments),
                                     workMinutes: Defaults[.pomodoroWorkMinutes],
                                     breakMinutes: Defaults[.pomodoroBreakMinutes])
        switch parsed {
        case let .failure(error):
            HUD.show(error.message, kind: .warning)
        case let .success(.control(control)):
            guard runs[noteID] != nil else { HUD.show("No timer running"); return }
            switch control {
            case .togglePause: togglePause(noteID: noteID)
            case .reset: reset(noteID: noteID)
            case .stop: stop(noteID: noteID)
            }
        case let .success(.start(spec)):
            let now = clock()
            if var existing = runs[noteID], existing.spec == spec, !existing.isFinished(at: now) {
                if existing.isPaused { existing.resume(at: now); runs[noteID] = existing; changed(noteID) }
                return
            }
            runs[noteID] = TimerRun(spec: spec, now: now)
            HUD.show(spec.startMessage, kind: .success)
            if spec.kind == .breathe { TimerOverlay.shared.showBreathing() }
            changed(noteID)
        }
    }

    public func stop(noteID: UUID) {
        guard runs.removeValue(forKey: noteID) != nil else { return }
        changed(noteID)
    }

    public func isRunning(noteID: UUID) -> Bool {
        guard let run = runs[noteID] else { return false }
        return !run.isPaused && !run.isFinished(at: clock())
    }

    public func status(noteID: UUID) -> String? { runs[noteID]?.statusText(at: clock()) }

    // MARK: Extras (palette, menu bar, overlay)

    public var runningNoteIDs: [UUID] { runs.keys.sorted { $0.uuidString < $1.uuidString } }

    public func run(noteID: UUID) -> TimerRun? { runs[noteID] }

    public func togglePause(noteID: UUID) {
        guard var run = runs[noteID] else { return }
        if run.isPaused { run.resume(at: clock()) } else { run.pause(at: clock()) }
        runs[noteID] = run
        changed(noteID)
    }

    public func reset(noteID: UUID) {
        guard var run = runs[noteID] else { return }
        run.reset(at: clock())
        if run.isPaused, case .countdown = run.spec.kind { run.resume(at: clock()) }
        runs[noteID] = run
        changed(noteID)
    }

    public func showFullScreen(noteID: UUID) {
        guard runs[noteID] != nil else { return }
        TimerOverlay.shared.showLive { [weak self] in
            guard let self, let run = self.runs[noteID] else { return nil }
            let snap = run.snapshot(at: self.clock())
            let phase: String
            switch snap.phase {
            case .running: phase = run.spec.kind == .stopwatch ? "Stopwatch" : "Countdown"
            case let .work(n): phase = "Work session \(n)"
            case let .rest(n): phase = "Break \(n)"
            case .breatheIn: phase = "Breathe in."
            case .breatheOut: phase = "Breathe out."
            case .finished: phase = "Done"
            }
            let title = run.spec.kind == .breathe ? phase : TimerFormat.clock(snap.seconds)
            let subtitle = [run.spec.kind == .breathe ? nil : phase, run.spec.name.isEmpty ? nil : run.spec.name,
                            snap.isPaused ? "paused" : nil].compactMap { $0 }.joined(separator: " · ")
            return TimerOverlay.Live(title: title, subtitle: subtitle, progress: snap.progress)
        }
    }

    // MARK: Ticking & events

    private func changed(_ noteID: UUID) {
        save()
        scheduleTicker()
        refreshMenuBarText()
        NotificationCenter.default.post(name: .jotterTimersDidChange, object: noteID)
    }

    private func scheduleTicker() {
        let now = clock()
        let active = runs.values.contains { !$0.isPaused && !$0.isFinished(at: now) }
        if active, ticker == nil {
            lastTick = now
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            t.tolerance = 0.1
            RunLoop.main.add(t, forMode: .common)
            ticker = t
        } else if !active {
            ticker?.invalidate(); ticker = nil
        }
    }

    private func tick() {
        let now = clock()
        purgeDeletedNotes()
        for (id, run) in runs where !run.isPaused {
            if let event = run.events(from: lastTick, to: now).last { announce(event, run: run, noteID: id) }
            NotificationCenter.default.post(name: .jotterTimersDidChange, object: id)
        }
        lastTick = now
        refreshMenuBarText()
        if !runs.values.contains(where: { !$0.isPaused && !$0.isFinished(at: now) }) {
            save()
            scheduleTicker()
        }
    }

    private func purgeDeletedNotes() {
        guard Services.store != nil else { return }
        for id in runs.keys where Services.store.note(id).map({ $0.isInVoid }) ?? true {
            runs.removeValue(forKey: id)
            save()
        }
    }

    private func announce(_ event: TimerEvent, run: TimerRun, noteID: UUID) {
        let name = run.spec.name
        let title: String, message: String, sound: String
        switch event {
        case .finished:
            title = name.isEmpty ? "Timer Complete" : name
            message = "Your countdown timer is over."
            sound = "Glass"
        case .workEnded:
            title = "Work Session Complete"
            message = "Take some time for yourself."
            sound = "Hero"
        case .breakEnded:
            if TimerOverlay.shared.breakNoteID == noteID { Defaults[.toolsKitNoPeekStreak].breakCompleted() }
            title = "Break Over"
            message = BreakContent.backToWork.randomElement() ?? ""
            sound = "Ping"
        }
        if Defaults[.timerSounds] { NSSound(named: NSSound.Name(sound))?.play() }
        let style = Defaults[.timerAlertStyle]
        if style != .notification {
            switch event {
            case .workEnded: TimerOverlay.shared.showBreak(breakScreen(noteID: noteID))
            case .finished:
                TimerOverlay.shared.showAlert(title: title, subtitle: "Wildlife fact-file", message: BreakContent.randomFact())
            case let .breakEnded(n):
                TimerOverlay.shared.showAlert(title: title, subtitle: name.isEmpty ? "Session \(n + 1)" : name, message: message)
            }
        }
        if style != .fullScreen { TimerNotifier.post(title: title, body: message) }
    }

    /// The break screen for the pomodoro on `noteID`.
    private func breakScreen(noteID: UUID) -> TimerOverlay.Break {
        TimerOverlay.Break(
            noteID: noteID,
            fact: BreakContent.randomFact(),
            remaining: { [weak self] in
                guard let self, let snap = self.runs[noteID]?.snapshot(at: self.clock()), case .rest = snap.phase else { return nil }
                return snap.remaining
            },
            isPaused: { [weak self] in self?.runs[noteID]?.isPaused ?? false },
            togglePause: { [weak self] in self?.togglePause(noteID: noteID) },
            end: { [weak self] in self?.stop(noteID: noteID) },
            peek: { Defaults[.toolsKitNoPeekStreak].peeked() },
            streak: { Defaults[.toolsKitNoPeekStreak] })
    }

    // MARK: Menu bar

    /// The timer whose current phase ends soonest (stopwatches only when nothing counts down).
    private func soonest(at now: Date) -> (UUID, TimerRun)? {
        let live = runs.filter { !$0.value.isFinished(at: now) }
        let counting = live.compactMap { entry in entry.value.snapshot(at: now).remaining.map { (entry, $0) } }
        if let best = counting.min(by: { ($0.0.value.isPaused ? 1 : 0, $0.1) < ($1.0.value.isPaused ? 1 : 0, $1.1) }) {
            return (best.0.key, best.0.value)
        }
        return live.max { $0.value.elapsed(at: now) < $1.value.elapsed(at: now) }.map { ($0.key, $0.value) }
    }

    /// The soonest timer's time left, shown next to the status-bar icon ("△ 04:37") when the setting is on.
    private func refreshMenuBarText() {
        let now = clock()
        guard Defaults[.timerInMenuBar], let (_, run) = soonest(at: now), run.spec.kind != .breathe else {
            MenuBarTimer.update(nil)
            return
        }
        MenuBarTimer.update(TimerFormat.clock(run.snapshot(at: now).seconds))
    }

    // MARK: Persistence

    private func save() {
        Defaults[.toolsKitTimers] = Dictionary(uniqueKeysWithValues: runs.map { ($0.key.uuidString, $0.value) })
    }

    private func restore() {
        let now = clock()
        for (key, var run) in Defaults[.toolsKitTimers] {
            guard let id = UUID(uuidString: key) else { continue }
            if run.pausedByQuit { run.resume(at: now) }
            runs[id] = run
        }
        refreshMenuBarText()
    }

    private func prepareForQuit() {
        let now = clock()
        if Defaults[.pauseTimersOnQuit] {
            for (id, var run) in runs where !run.isPaused && !run.isFinished(at: now) {
                run.pause(at: now)
                run.pausedByQuit = true
                runs[id] = run
            }
        }
        save()
    }

    /// Re-attaches a `stopwatch` / `countdown` / `pomodoro` keyword when the caller passed only the arguments.
    private func withNoteKeyword(noteID: UUID, arguments: String) -> String {
        guard Services.store != nil, let note = Services.store.note(noteID) else { return arguments }
        let keyword = NoteMode.detect(firstLine: note.title).keyword
        guard ["stopwatch", "countdown", "pomodoro"].contains(keyword),
              arguments.split(separator: " ").first?.lowercased() != keyword else { return arguments }
        return keyword + " " + arguments
    }
}

/// System notifications (only from a real app bundle — `UNUserNotificationCenter` needs one).
enum TimerNotifier {
    private static let presenter = ForegroundPresenter()

    @MainActor static func post(title: String, body: String) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = presenter }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString,
                                                                         content: content, trigger: nil))
        }
    }

    /// Shows banners while Jotter is frontmost.
    private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .list])
        }
    }
}
