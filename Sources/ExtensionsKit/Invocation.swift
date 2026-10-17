import Foundation

public enum CommandType: String, Sendable, CaseIterable {
    case insert, replaceLine, replaceAll, openURL
}

public enum ParameterType: String, Sendable {
    case float, int, string, paragraph, bool, expression

    init(js: String) {
        self = js == "mathExpression" ? .expression : ParameterType(rawValue: js) ?? .string
    }
    var isText: Bool { self == .string || self == .paragraph }
}

/// A JSON-compatible value (parameter defaults, preference values, coerced arguments).
public enum JSONValue: Codable, Sendable, Equatable {
    case null, bool(Bool), number(Double), string(String), list([String])

    public init(any: Any?) {
        switch any {
        case let n as NSNumber:
            self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        case let s as String: self = .string(s)
        case let a as [Any]: self = .list(a.map { "\($0)" })
        default: self = .null
        }
    }

    public var foundation: Any {
        switch self {
        case .null: NSNull()
        case .bool(let b): b
        case .number(let n): n.rounded() == n && abs(n) < 1e15 ? Int(n) as Any : n as Any
        case .string(let s): s
        case .list(let l): l
        }
    }

    public var text: String {
        switch self {
        case .null: ""
        case .bool(let b): b ? "true" : "false"
        case .number: "\(foundation)"
        case .string(let s): s
        case .list(let l): l.joined(separator: ", ")
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else { self = .list(try c.decode([String].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .list(let l): try c.encode(l)
        }
    }
}

public struct ParameterSpec: Sendable, Equatable {
    public var name: String
    public var type: ParameterType
    public var helpText: String
    public var defaultValue: JSONValue
    public var required: Bool

    public init(name: String, type: ParameterType, helpText: String = "", defaultValue: JSONValue = .null, required: Bool = true) {
        self.name = name; self.type = type; self.helpText = helpText; self.defaultValue = defaultValue; self.required = required
    }
}

public struct TutorialSpec: Sendable, Equatable {
    public var command: String
    public var description: String
}

/// A command as registered by an extension's script.
public struct CommandSpec: Sendable, Equatable {
    public var name: String
    public var aliases: [String]
    public var type: CommandType
    public var helpText: String
    public var parameters: [ParameterSpec]
    public var tutorials: [TutorialSpec]

    public init(name: String, aliases: [String] = [], type: CommandType, helpText: String = "",
                parameters: [ParameterSpec], tutorials: [TutorialSpec] = []) {
        self.name = name; self.aliases = aliases; self.type = type; self.helpText = helpText
        self.parameters = parameters; self.tutorials = tutorials
    }

    public var signature: String {
        parameters.isEmpty ? "::\(name)"
            : "::\(name)(" + parameters.map { $0.required ? $0.name : $0.name + "?" }.joined(separator: ", ") + ")"
    }
}

/// A parsed `::name(arg, "arg, 2", 3)`.
public struct ExtensionInvocation: Equatable, Sendable {
    public var name: String
    /// Arguments with surrounding quotes removed and whitespace trimmed.
    public var arguments: [String]
    /// The original text of each argument (untrimmed, quotes kept), for re-joining surplus text arguments.
    var rawArguments: [String]

    public static func parse(_ text: String) throws -> ExtensionInvocation {
        var rest = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if rest.hasPrefix("::") { rest = rest.dropFirst(2) }
        let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        guard !name.isEmpty else { throw ExtensionError.script("Type a command name after ::") }
        rest = rest.dropFirst(name.count).drop { $0 == " " }
        guard !rest.isEmpty else { return ExtensionInvocation(name: String(name), arguments: [], rawArguments: []) }
        guard rest.first == "(" else { throw ExtensionError.script("Unexpected text after ::\(name)") }
        let raw = try split(rest.dropFirst())
        let args = raw.map(clean)
        if args.count == 1 && args[0].isEmpty && raw[0].trimmingCharacters(in: .whitespaces).isEmpty {
            return ExtensionInvocation(name: String(name), arguments: [], rawArguments: [])
        }
        return ExtensionInvocation(name: String(name), arguments: args, rawArguments: raw)
    }

    /// Splits the text after "(" on top-level commas up to the matching ")".
    private static func split(_ body: Substring) throws -> [String] {
        var parts: [String] = [], current = ""
        var quote: Character?, escaped = false, depth = 0, closed = false
        var index = body.startIndex
        while index < body.endIndex {
            let c = body[index]
            index = body.index(after: index)
            if let q = quote {
                current.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == q { quote = nil }
                continue
            }
            switch c {
            case "\"", "'", "“":
                // Quotes only open an argument; an apostrophe inside a word ("don't") is plain text.
                if current.trimmingCharacters(in: .whitespaces).isEmpty { quote = c == "“" ? "”" : c }
                current.append(c)
            case "(": depth += 1; current.append(c)
            case ")" where depth > 0: depth -= 1; current.append(c)
            case ")": closed = true
            case "," where depth == 0: parts.append(current); current = ""
            default: current.append(c)
            }
            if closed { break }
        }
        if quote != nil { throw ExtensionError.script("Missing closing quote") }
        guard closed else { throw ExtensionError.script("Missing closing parenthesis") }
        guard body[index...].trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ExtensionError.script("Unexpected text after the closing parenthesis")
        }
        parts.append(current)
        return parts
    }

    private static func clean(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2, let first = t.first, let last = t.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") || (first == "“" && last == "”") else { return t }
        var out = "", escaped = false
        for c in t.dropFirst().dropLast() {
            if escaped {
                // Only quote, backslash, \n and \t are escapes; anything else keeps its backslash (regex patterns).
                switch c {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "\\", "\"", "'", "”": out.append(c)
                default: out.append("\\"); out.append(c)
                }
                escaped = false
            } else if c == "\\" { escaped = true } else { out.append(c) }
        }
        return out
    }

    /// Coerces arguments to the declared parameter types (defaults for missing optional ones).
    /// `evaluate` computes `expression` parameters that are not plain numbers.
    public func coerced(for command: CommandSpec, evaluate: (String) -> Result<Double, Error>) throws -> [JSONValue] {
        let params = command.parameters
        var args = arguments
        if args.count > params.count {
            guard let last = params.last, last.type.isText else {
                throw ExtensionError.script("::\(command.name) takes \(params.count) parameter\(params.count == 1 ? "" : "s"), got \(args.count)")
            }
            let joined = rawArguments[(params.count - 1)...].joined(separator: ",")
            args = Array(args.prefix(params.count - 1)) + [Self.clean(joined)]
        }
        return try params.enumerated().map { i, p in
            let value = i < args.count ? args[i] : nil
            let missing = value == nil || (!p.type.isText && value!.isEmpty)
            if missing {
                if p.required { throw ExtensionError.script("Required parameter '\(p.name)' is missing") }
                return p.defaultValue
            }
            let v = value!
            switch p.type {
            case .string, .paragraph: return .string(v)
            case .int:
                if let n = Int(v.replacingOccurrences(of: "+", with: "")) { return .number(Double(n)) }
                if let d = Double(v), d.rounded() == d { return .number(d) }
                throw ExtensionError.script("Parameter '\(p.name)' must be a whole number")
            case .float:
                if let d = Double(v) { return .number(d) }
                throw ExtensionError.script("Parameter '\(p.name)' must be a number")
            case .bool:
                switch v.lowercased() {
                case "true", "yes", "1", "on", "y": return .bool(true)
                case "false", "no", "0", "off", "n": return .bool(false)
                default: throw ExtensionError.script("Parameter '\(p.name)' must be true or false")
                }
            case .expression:
                if let d = Double(v) { return .number(d) }
                switch evaluate(v) {
                case .success(let d): return .number(d)
                case .failure(let e): throw ExtensionError.script("Parameter '\(p.name)': \(e.localizedDescription)")
                }
            }
        }
    }
}

/// What a command receives of the note, per its extension's data scope.
public struct ScopedText: Equatable, Sendable {
    public var line: String
    public var fullText: String

    public init(invocation: String, line: String, note: String, scope: DataScope) {
        let strippedLine = Self.remove(invocation, from: line)
        switch scope {
        case .none: self.line = ""; fullText = ""
        case .line: self.line = strippedLine; fullText = strippedLine
        case .full:
            self.line = strippedLine
            var lines = note.components(separatedBy: "\n")
            if let i = lines.firstIndex(of: line) ?? lines.firstIndex(where: { $0.contains(invocation) }) {
                let stripped = Self.remove(invocation, from: lines[i])
                if stripped.trimmingCharacters(in: .whitespaces).isEmpty { lines.remove(at: i) } else { lines[i] = stripped }
                fullText = lines.joined(separator: "\n")
            } else {
                fullText = note
            }
        }
    }

    static func remove(_ invocation: String, from line: String) -> String {
        guard !invocation.isEmpty, let r = line.range(of: invocation) else { return line }
        var out = line
        out.removeSubrange(r)
        while out.last == " " || out.last == "\t" { out.removeLast() }
        return out
    }
}
