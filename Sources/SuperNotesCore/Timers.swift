import Foundation

/// What a `timer` note runs.
public enum TimerKind: Codable, Equatable, Sendable {
    case stopwatch
    case countdown(TimeInterval)
    case pomodoro(work: TimeInterval, rest: TimeInterval)
    case breathe
}

public struct TimerSpec: Codable, Equatable, Sendable {
    public var kind: TimerKind
    public var name: String
    public init(kind: TimerKind, name: String = "") { self.kind = kind; self.name = name }

    /// Short confirmation shown when the timer starts.
    public var startMessage: String {
        switch kind {
        case .stopwatch: "Stopwatch started"
        case .countdown: "Countdown started"
        case let .pomodoro(work, rest): "\(Int(work / 60))/\(Int(rest / 60)) Pomodoro started"
        case .breathe: "Breathing started"
        }
    }
}

public enum TimerControl: Equatable, Sendable { case togglePause, reset, stop }

public enum TimerCommand: Equatable, Sendable {
    case start(TimerSpec)
    case control(TimerControl)
}

public enum TimerParseError: Error, Equatable, Sendable {
    case zeroCountdown, zeroPomodoro, tooManyNumbers, unparseable

    public var message: String {
        switch self {
        case .zeroCountdown: "Cannot countdown zero minutes"
        case .zeroPomodoro: "Pomodoro start time and break time cannot be zero"
        case .tooManyNumbers: "Timer only accepts 2 numbers."
        case .unparseable: "Unable to parse timer command."
        }
    }
}

public extension TimerSpec {
    /// Parses a timer note's first-line arguments (optionally still prefixed with the keyword), e.g. "", "25m",
    /// "10:00", "1h30m", "5m tea", "5:30 : laundry", "pomodoro 52 17", "countdown 5m", "breathe", "p".
    static func parse(_ arguments: String, workMinutes: Int = 25, breakMinutes: Int = 5)
        -> Result<TimerCommand, TimerParseError> {
        let (head, colonName) = splitName(arguments.trimmingCharacters(in: .whitespacesAndNewlines))
        var tokens = head.split(whereSeparator: \.isWhitespace).map { String($0).lowercased() }

        var name = colonName
        var hint: String?
        if let first = tokens.first, ["timer", "stopwatch", "countdown", "pomodoro", "pomo", "breathe", "breath"].contains(first) {
            hint = first == "timer" ? nil : first
            tokens.removeFirst()
            // "timer pomo …": the second word can still carry the kind.
            if hint == nil, let next = tokens.first, ["stopwatch", "countdown", "pomodoro", "pomo", "breathe", "breath"].contains(next) {
                hint = next; tokens.removeFirst()
            }
        }

        if hint == nil, tokens.count == 1, name.isEmpty {
            switch tokens[0] {
            case "p", "pause", "resume": return .success(.control(.togglePause))
            case "r", "reset": return .success(.control(.reset))
            case "s", "stop": return .success(.control(.stop))
            default: break
            }
        }

        // Leading duration tokens; the remaining words form the name.
        var durations: [TimeInterval] = []
        var index = 0
        while index < tokens.count, let d = duration(tokens[index]) {
            // "1h 30m" — a token with a smaller unit than the previous one extends it; "50m 10m" stays two values.
            if let last = durations.last, unitRank(tokens[index - 1]) > unitRank(tokens[index]), unitRank(tokens[index]) > 0 {
                durations[durations.count - 1] = last + d
            } else {
                durations.append(d)
            }
            index += 1
        }
        let rest = tokens[index...].joined(separator: " ")
        if !rest.isEmpty {
            // Keep the user's original casing for the name.
            let originalWords = head.split(whereSeparator: \.isWhitespace).suffix(tokens.count - index)
            let words = originalWords.joined(separator: " ")
            name = name.isEmpty ? words : words + " " + name
        }

        switch hint {
        case "stopwatch":
            return durations.isEmpty ? .success(.start(TimerSpec(kind: .stopwatch, name: name))) : .failure(.unparseable)
        case "breathe", "breath":
            return durations.isEmpty ? .success(.start(TimerSpec(kind: .breathe, name: name))) : .failure(.unparseable)
        case "pomodoro", "pomo":
            return pomodoro(durations, name: name, workMinutes: workMinutes, breakMinutes: breakMinutes)
        case "countdown":
            guard durations.count == 1 else { return .failure(durations.isEmpty ? .unparseable : .tooManyNumbers) }
            return countdown(durations[0], name: name)
        default:
            switch durations.count {
            case 0: return .success(.start(TimerSpec(kind: .stopwatch, name: name)))
            case 1: return countdown(durations[0], name: name)
            case 2: return pomodoro(durations, name: name, workMinutes: workMinutes, breakMinutes: breakMinutes)
            default: return .failure(.tooManyNumbers)
            }
        }
    }

    private static func countdown(_ seconds: TimeInterval, name: String) -> Result<TimerCommand, TimerParseError> {
        seconds > 0 ? .success(.start(TimerSpec(kind: .countdown(seconds), name: name))) : .failure(.zeroCountdown)
    }

    private static func pomodoro(_ durations: [TimeInterval], name: String, workMinutes: Int, breakMinutes: Int)
        -> Result<TimerCommand, TimerParseError> {
        guard durations.count <= 2 else { return .failure(.tooManyNumbers) }
        let work = durations.first ?? TimeInterval(workMinutes * 60)
        let rest = durations.count == 2 ? durations[1] : TimeInterval(breakMinutes * 60)
        guard work > 0, rest > 0 else { return .failure(.zeroPomodoro) }
        return .success(.start(TimerSpec(kind: .pomodoro(work: work, rest: rest), name: name)))
    }

    /// Splits "5:30 : laundry" / "5m: tea" into the timing part and the name. A colon between two digits is time.
    private static func splitName(_ text: String) -> (String, String) {
        let chars = Array(text)
        for (i, c) in chars.enumerated() where c == ":" {
            let before = i > 0 ? chars[i - 1] : " ", after = i + 1 < chars.count ? chars[i + 1] : " "
            if before.isNumber && after.isNumber { continue }
            let head = String(chars[..<i]).trimmingCharacters(in: .whitespaces)
            let name = String(chars[(i + 1)...]).trimmingCharacters(in: .whitespaces)
            return (head, name)
        }
        return (text, "")
    }

    /// 3 for hours, 2 for minutes, 1 for seconds (by the token's last unit), 0 for bare numbers and clock times.
    private static func unitRank(_ token: String) -> Int {
        let unit = token.reversed().prefix { $0.isLetter }.reversed().first
        switch unit { case "h": return 3; case "m": return 2; case "s": return 1; default: return 0 }
    }

    /// "5" (minutes), "1.5", "25m", "25min", "90s", "2h", "1h30m", "10:00" (m:ss), "1:30:00" (h:mm:ss).
    static func duration(_ token: String) -> TimeInterval? {
        if token.contains(":") {
            let parts = token.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
            guard parts.count <= 3, parts.allSatisfy({ $0 != nil }) else { return nil }
            let values = parts.map { $0! }
            guard values.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
            return TimeInterval(values.reduce(0) { $0 * 60 + $1 })
        }
        if let minutes = Double(token) { return minutes >= 0 ? minutes * 60 : nil }
        var total: TimeInterval = 0, number = "", sawUnit = false
        var rest = Substring(token)
        while let c = rest.first {
            if c.isNumber || c == "." { number.append(c); rest.removeFirst(); continue }
            guard let value = Double(number) else { return nil }
            let unit: TimeInterval
            if rest.hasPrefix("hr") || rest.hasPrefix("h") { unit = 3600; rest = rest.drop { $0.isLetter } }
            else if rest.hasPrefix("min") || rest.hasPrefix("m") { unit = 60; rest = rest.drop { $0.isLetter } }
            else if rest.hasPrefix("sec") || rest.hasPrefix("s") { unit = 1; rest = rest.drop { $0.isLetter } }
            else { return nil }
            total += value * unit; number = ""; sawUnit = true
        }
        guard sawUnit, number.isEmpty else { return nil }
        return total
    }
}

/// Clock formatting for timers.
public enum TimerFormat {
    /// "04:05", "1:02:03".
    public static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    /// "25 min", "1 h 30 min", "45 s".
    public static func spoken(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) s" }
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) h") }
        if m > 0 { parts.append("\(m) min") }
        if sec > 0 && h == 0 { parts.append("\(sec) s") }
        return parts.joined(separator: " ")
    }
}

/// The running timer's time left for the status-bar item ("04:37"), or nil when nothing should show there.
/// The timer publishes it; the app's single status item displays it.
@MainActor
public enum MenuBarTimer {
    public static let didChange = Notification.Name("SuperNotesMenuBarTimerDidChange")
    public private(set) static var text: String?

    public static func update(_ text: String?) {
        guard text != self.text else { return }
        self.text = text
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
