import Foundation
import JotterCore

/// Something a running timer announces.
public enum TimerEvent: Equatable, Sendable {
    case finished
    /// Work session `n` (1-based) ended; the break starts.
    case workEnded(Int)
    /// Break `n` ended; work session `n + 1` starts.
    case breakEnded(Int)
}

/// A point-in-time view of a timer.
public struct TimerSnapshot: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case running, work(Int), rest(Int), breatheIn, breatheOut, finished }
    public var phase: Phase
    /// Seconds shown: elapsed for stopwatches, remaining otherwise.
    public var seconds: TimeInterval
    /// Seconds until this phase ends (nil for stopwatches).
    public var remaining: TimeInterval?
    /// 0…1 progress through the current phase (stopwatches: 0).
    public var progress: Double
    public var isPaused: Bool
}

/// The timer state machine. Pure value type: every query takes an explicit `now`, so tests drive it with a fake clock.
public struct TimerRun: Codable, Equatable, Sendable {
    public var spec: TimerSpec
    /// Running time accumulated before the current segment.
    public var accumulated: TimeInterval
    /// Start of the current running segment; nil while paused.
    public var segmentStart: Date?
    /// Paused automatically when the app quit (resumed on the next launch).
    public var pausedByQuit: Bool

    public static let breatheIn: TimeInterval = 4
    public static let breatheOut: TimeInterval = 6

    public init(spec: TimerSpec, now: Date) {
        self.spec = spec; accumulated = 0; segmentStart = now; pausedByQuit = false
    }

    public var isPaused: Bool { segmentStart == nil }

    public func elapsed(at now: Date) -> TimeInterval {
        accumulated + (segmentStart.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    public mutating func pause(at now: Date) {
        guard let start = segmentStart else { return }
        accumulated += max(0, now.timeIntervalSince(start))
        segmentStart = nil
    }

    public mutating func resume(at now: Date) {
        guard segmentStart == nil, !isFinished(at: now) else { return }
        segmentStart = now; pausedByQuit = false
    }

    /// Back to zero, keeping the running/paused state.
    public mutating func reset(at now: Date) {
        accumulated = 0
        if segmentStart != nil { segmentStart = now }
    }

    public func isFinished(at now: Date) -> Bool {
        if case let .countdown(total) = spec.kind { return elapsed(at: now) >= total }
        return false
    }

    /// Countdowns: the absolute end date while running.
    public func endDate(at now: Date) -> Date? {
        guard let remaining = snapshot(at: now).remaining, !isPaused else { return nil }
        return now.addingTimeInterval(remaining)
    }

    public func snapshot(at now: Date) -> TimerSnapshot {
        let t = elapsed(at: now)
        switch spec.kind {
        case .stopwatch:
            return TimerSnapshot(phase: .running, seconds: t, remaining: nil, progress: 0, isPaused: isPaused)
        case let .countdown(total):
            let left = max(0, total - t)
            return TimerSnapshot(phase: left <= 0 ? .finished : .running, seconds: left.rounded(.up), remaining: left,
                                 progress: min(1, t / total), isPaused: isPaused)
        case let .pomodoro(work, rest):
            let cycle = Int(t / (work + rest)), position = t.truncatingRemainder(dividingBy: work + rest)
            if position < work {
                let left = work - position
                return TimerSnapshot(phase: .work(cycle + 1), seconds: left.rounded(.up), remaining: left,
                                     progress: position / work, isPaused: isPaused)
            }
            let left = work + rest - position
            return TimerSnapshot(phase: .rest(cycle + 1), seconds: left.rounded(.up), remaining: left,
                                 progress: (position - work) / rest, isPaused: isPaused)
        case .breathe:
            let breath = Self.breatheIn + Self.breatheOut, position = t.truncatingRemainder(dividingBy: breath)
            let inhaling = position < Self.breatheIn
            let progress = inhaling ? position / Self.breatheIn : (position - Self.breatheIn) / Self.breatheOut
            return TimerSnapshot(phase: inhaling ? .breatheIn : .breatheOut, seconds: t, remaining: nil,
                                 progress: progress, isPaused: isPaused)
        }
    }

    /// Events crossed between two instants (both measured on this run's clock).
    public func events(from start: Date, to end: Date) -> [TimerEvent] {
        let a = elapsed(at: start), b = elapsed(at: end)
        guard b > a else { return [] }
        switch spec.kind {
        case let .countdown(total):
            return a < total && b >= total ? [.finished] : []
        case let .pomodoro(work, rest):
            func phaseIndex(_ t: TimeInterval) -> Int {
                let cycle = Int(t / (work + rest))
                return cycle * 2 + (t.truncatingRemainder(dividingBy: work + rest) < work ? 0 : 1)
            }
            let from = phaseIndex(a), to = phaseIndex(b)
            guard to > from else { return [] }
            return (from + 1 ... to).map { $0 % 2 == 1 ? .workEnded($0 / 2 + 1) : .breakEnded($0 / 2) }
        case .stopwatch, .breathe:
            return []
        }
    }

    /// The text the editor shows next to the timer line, e.g. "24:59 · work 1 · tea".
    public func statusText(at now: Date) -> String {
        let snap = snapshot(at: now)
        var parts: [String]
        switch snap.phase {
        case .running: parts = [TimerFormat.clock(snap.seconds)]
        case let .work(n): parts = [TimerFormat.clock(snap.seconds), "work \(n)"]
        case let .rest(n): parts = [TimerFormat.clock(snap.seconds), "break \(n)"]
        case .breatheIn: parts = ["Breathe in."]
        case .breatheOut: parts = ["Breathe out."]
        case .finished: parts = ["Done"]
        }
        if !spec.name.isEmpty { parts.append(spec.name) }
        if snap.isPaused && snap.phase != .finished { parts.append("paused") }
        return parts.joined(separator: " · ")
    }
}
