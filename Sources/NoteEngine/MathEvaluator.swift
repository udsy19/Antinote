import Foundation

public enum MathError: Error, Equatable, LocalizedError {
    case syntax
    case incompatible(String, String)
    case divisionByZero
    case noRate(String)
    case noPreviousAnswer
    case alreadyDefined
    case invalidArgument(String)
    case notANumber

    public var errorDescription: String? {
        switch self {
        case .syntax: "Invalid expression"
        case let .incompatible(a, b): "Can't combine \(a) and \(b)"
        case .divisionByZero: "Division by zero"
        case let .noRate(code): "No exchange rate for \(code)"
        case .noPreviousAnswer: "No previous answer"
        case .alreadyDefined: "Already defined"
        case let .invalidArgument(f): "Invalid argument for \(f)"
        case .notANumber: "Not a number"
        }
    }

    /// Errors about meaning (not just incomplete typing); shown on lenient lines that are pure math.
    var isSemantic: Bool {
        switch self {
        case .syntax, .noPreviousAnswer: false
        default: true
        }
    }
}

/// A value with an optional unit (or currency); percentages keep their raw number (15% → 15, isPercent).
struct Quantity: Hashable {
    var value: Double
    var unit: MathUnit?
    var isPercent = false

    init(_ value: Double, _ unit: MathUnit? = nil, percent: Bool = false) {
        self.value = value; self.unit = unit; self.isPercent = percent
    }
    var fraction: Double { isPercent ? value / 100 : value }
}

/// Everything a line's evaluation depends on besides its text.
struct MathContext {
    var variables: [String: Quantity] = [:]
    var answer: Quantity?
    var settings: MathSettings
    var rates: ExchangeRates

    var answerWords: Set<String> { ["ans", "prev", settings.answerWord.lowercased()] }

    func currency(_ code: String) -> MathUnit {
        let resolved = CurrencyCatalog.resolve(code, primary: settings.primaryCurrency)
        return .currency(resolved, usdPerUnit: rates.usdPerUnit(resolved))
    }
}

/// The outcome of evaluating one expression.
struct Evaluation {
    var quantity: Quantity
    /// Number of operations performed (operators, functions, conversions, percent-of, unit sums).
    var operations: Int
    /// Descriptive words were ignored.
    var hadNoise: Bool
    /// The expression was a single currency/unit literal with nothing else.
    var isLoneLiteral: Bool
}

enum MathEvaluator {
    /// Evaluates an expression; returns the error together with whether the text contained descriptive words.
    static func evaluate(_ text: String, context: MathContext) -> Result<Evaluation, EvaluationFailure> {
        let raw = MathLexer.lex(text, variables: Array(context.variables.keys))
        var resolver = Resolver(raw: raw, context: context)
        let tokens = resolver.resolve()
        let hasNumber = tokens.contains { if case .number = $0 { true } else if case .value = $0 { true } else { false } }
        var parser = Parser(tokens: tokens, context: context)
        do {
            var q = try parser.parseExpression()
            guard parser.atEnd else { throw MathError.syntax }
            guard q.value.isFinite else { throw MathError.notANumber }
            if q.value == 0 { q.value = 0 } // drop negative zero
            let lone = parser.operations == 0 && tokens.count <= 3
            return .success(Evaluation(quantity: q, operations: parser.operations, hadNoise: resolver.noise, isLoneLiteral: lone))
        } catch {
            return .failure(EvaluationFailure(error: error as? MathError ?? .syntax, hadNoise: resolver.noise, hasNumber: hasNumber))
        }
    }

    struct EvaluationFailure: Error {
        var error: MathError
        var hadNoise: Bool
        var hasNumber: Bool
    }

    // MARK: - Quantity arithmetic

    static func convert(_ q: Quantity, to u: MathUnit) throws -> Quantity {
        guard let from = q.unit else { return Quantity(q.value, u) }
        if from.id == u.id { return Quantity(q.value, u) }
        guard from.dimension == u.dimension else { throw MathError.incompatible(from.id, u.id) }
        if u.isCurrency {
            guard from.factor > 0 else { throw MathError.noRate(from.id) }
            guard u.factor > 0 else { throw MathError.noRate(u.id) }
        }
        return Quantity(u.fromBase(from.toBase(q.value)), u)
    }

    static func add(_ a: Quantity, _ b: Quantity, subtract: Bool) throws -> Quantity {
        let sign: Double = subtract ? -1 : 1
        switch (a.isPercent, b.isPercent) {
        case (true, true): return Quantity(a.value + sign * b.value, percent: true)
        case (false, true): return Quantity(a.value * (1 + sign * b.value / 100), a.unit)
        case (true, false): return try add(Quantity(a.fraction), b, subtract: subtract)
        case (false, false): break
        }
        guard let ua = a.unit else { return Quantity(a.value + sign * b.value, b.unit) }
        guard let ub = b.unit else { return Quantity(a.value + sign * b.value, ua) }
        guard ua.dimension == ub.dimension else { throw MathError.incompatible(ua.id, ub.id) }
        let bc = try convert(b, to: ua)
        return Quantity(a.value + sign * bc.value, ua)
    }

    static func multiply(_ a: Quantity, _ b: Quantity) throws -> Quantity {
        if a.isPercent && b.isPercent { return Quantity(a.value * b.value / 100, percent: true) }
        switch (a.unit, b.unit) {
        case (nil, nil): return Quantity(a.fraction * b.fraction)
        case let (u?, nil): return Quantity(a.value * b.fraction, u)
        case let (nil, u?): return Quantity(a.fraction * b.value, u)
        case let (ua?, ub?):
            guard ua.dimension == .length, ub.dimension == .length else { throw MathError.incompatible(ua.id, ub.id) }
            let area = UnitCatalog.area(for: ua.id)
            let bc = try convert(b, to: ua)
            let product = Quantity(a.value * bc.value, area)
            // Lengths without a matching area unit (e.g. miles of light years) fall back to m².
            if area.id == ua.id + "²" { return product }
            return Quantity(ua.toBase(a.value) * ub.toBase(b.value), area)
        }
    }

    static func divide(_ a: Quantity, _ b: Quantity) throws -> Quantity {
        guard b.value != 0 else { throw MathError.divisionByZero }
        if b.isPercent { return Quantity(a.value / b.fraction, a.unit, percent: a.isPercent) }
        if a.isPercent, b.unit == nil { return Quantity(a.value / b.value, percent: true) }
        switch (a.unit, b.unit) {
        case (nil, nil): return Quantity(a.value / b.value)
        case let (u?, nil): return Quantity(a.value / b.value, u)
        case let (nil, u?): throw MathError.incompatible("number", u.id)
        case let (ua?, ub?):
            if ua.dimension == ub.dimension {
                let bc = try convert(b, to: ua)
                guard bc.value != 0 else { throw MathError.divisionByZero }
                return Quantity(a.value / bc.value)
            }
            if ua.dimension == .length, ub.dimension == .time {
                let speed = UnitCatalog.speed(length: ua.id, time: ub.id)
                return Quantity(speed.fromBase(ua.toBase(a.value) / ub.toBase(b.value)), speed)
            }
            throw MathError.incompatible(ua.id, ub.id)
        }
    }

    static func modulo(_ a: Quantity, _ b: Quantity) throws -> Quantity {
        let bc = (a.unit != nil && b.unit != nil) ? try convert(b, to: a.unit!) : b
        guard bc.value != 0 else { throw MathError.divisionByZero }
        return Quantity(a.value.truncatingRemainder(dividingBy: bc.value), a.unit ?? b.unit)
    }

    static func power(_ a: Quantity, _ b: Quantity) throws -> Quantity {
        guard b.unit == nil else { throw MathError.incompatible(a.unit?.id ?? "number", b.unit!.id) }
        if let u = a.unit {
            guard u.dimension == .length, b.fraction == 2 else { throw MathError.incompatible(u.id, "^") }
            return try multiply(a, a)
        }
        return Quantity(pow(a.fraction, b.fraction))
    }

    static func apply(_ name: String, _ args: [Quantity]) throws -> Quantity {
        guard let first = args.first else { throw MathError.invalidArgument(name) }
        func plain(_ q: Quantity) throws -> Double {
            guard q.unit == nil else { throw MathError.invalidArgument(name) }
            return q.fraction
        }
        func angle(_ q: Quantity) throws -> Double {
            if let u = q.unit {
                guard u.dimension == .angle else { throw MathError.invalidArgument(name) }
                return u.toBase(q.value)
            }
            return q.value
        }
        func checked(_ v: Double) throws -> Quantity {
            guard v.isFinite else { throw MathError.invalidArgument(name) }
            return Quantity(v)
        }
        switch name {
        case "sqrt":
            let v = try plain(first)
            guard v >= 0 else { throw MathError.invalidArgument(name) }
            return Quantity(v.squareRoot())
        case "cbrt": return Quantity(cbrt(try plain(first)))
        case "abs": return Quantity(Swift.abs(first.value), first.unit, percent: first.isPercent)
        case "floor": return Quantity(first.value.rounded(.down), first.unit, percent: first.isPercent)
        case "ceil": return Quantity(first.value.rounded(.up), first.unit, percent: first.isPercent)
        case "round":
            let digits = args.count > 1 ? try plain(args[1]) : 0
            let scale = pow(10, digits.rounded())
            return Quantity((first.value * scale).rounded() / scale, first.unit, percent: first.isPercent)
        case "sin": return Quantity(Foundation.sin(try angle(first)))
        case "cos": return Quantity(Foundation.cos(try angle(first)))
        case "tan": return try checked(Foundation.tan(try angle(first)))
        case "asin": return try checked(Foundation.asin(try plain(first)))
        case "acos": return try checked(Foundation.acos(try plain(first)))
        case "atan": return Quantity(Foundation.atan(try plain(first)))
        case "ln": return try checked(Foundation.log(try plain(first)))
        case "log2": return try checked(Foundation.log2(try plain(first)))
        case "exp": return try checked(Foundation.exp(try plain(first)))
        case "log":
            let v = try plain(first)
            if args.count > 1 { return try checked(Foundation.log(v) / Foundation.log(try plain(args[1]))) }
            return try checked(Foundation.log10(v))
        case "min", "max":
            var best = first
            for q in args.dropFirst() {
                let c = best.unit != nil && q.unit != nil ? try convert(q, to: best.unit!) : q
                if name == "min" ? c.value < best.value : c.value > best.value { best = Quantity(c.value, best.unit ?? q.unit, percent: q.isPercent) }
            }
            return best
        default: throw MathError.syntax
        }
    }
}

// MARK: - Resolution: raw tokens → meaningful tokens (descriptive words dropped)

enum Token: Equatable {
    case number(Double)
    case unit(MathUnit)
    /// Currency symbol before the amount.
    case prefix(MathUnit)
    case op(Op)
    case percent, lparen, rparen, comma, of, off, convert
    case function(String)
    case value(Quantity)
    case missingAnswer
}

private struct Resolver {
    let raw: [RawToken]
    let context: MathContext
    var noise = false
    private var out: [Token] = []

    init(raw: [RawToken], context: MathContext) { self.raw = raw; self.context = context }

    private static let scales: [String: Double] = ["thousand": 1e3, "million": 1e6, "billion": 1e9, "trillion": 1e12]
    private static let conversionWords: Set<String> = ["in", "to", "as", "into"]

    private var prevIsNumber: Bool { if case .number? = out.last { true } else { false } }
    private var prevIsConvert: Bool { out.last == .convert }
    private var prevEndsValue: Bool {
        switch out.last {
        case .number?, .unit?, .rparen?, .value?, .percent?, .missingAnswer?: true
        default: false
        }
    }

    /// The unit or currency a token names, if it can be a conversion target or a postfix unit.
    private func unitOrCurrency(_ t: RawToken) -> MathUnit? {
        switch t {
        case .unitPhrase(let u): return u
        case .currencySymbol(let code): return context.currency(code)
        case .word(let w):
            if w.count >= 3, w == w.uppercased(), CurrencyCatalog.isKnown(w) { return context.currency(w) }
            if let u = UnitCatalog.lookup(w) { return u }
            return CurrencyCatalog.code(forWord: w, primary: context.settings.primaryCurrency).map(context.currency)
        default: return nil
        }
    }

    private func startsOperand(_ t: RawToken?) -> Bool {
        switch t {
        case .number?, .lparen?, .currencySymbol?, .variable?: true
        case .word(let w)?: MathLexer.functions.contains(w.lowercased()) || ["pi", "e", "tau"].contains(w.lowercased())
            || context.answerWords.contains(w.lowercased())
        default: false
        }
    }

    mutating func resolve() -> [Token] {
        for (i, t) in raw.enumerated() {
            let next = i + 1 < raw.count ? raw[i + 1] : nil
            switch t {
            case .number(let n): out.append(.number(n))
            case .op(let op): out.append(.op(op))
            case .lparen: out.append(.lparen)
            case .rparen: out.append(.rparen)
            case .comma: out.append(.comma)
            case .percent:
                if prevEndsValue { out.append(.percent) } else { noise = true }
            case .variable(let name): out.append(.value(context.variables[name]!))
            case .opPhrase(let op):
                if prevEndsValue { out.append(.op(op)) } else { noise = true }
            case .currencySymbol(let code):
                if prevIsNumber || prevIsConvert { out.append(.unit(context.currency(code))) }
                else if case .number? = next { out.append(.prefix(context.currency(code))) }
                else if case .op(.sub)? = next { out.append(.prefix(context.currency(code))) }
                else { noise = true }
            case .unitPhrase(let u):
                if prevIsNumber || prevIsConvert { out.append(.unit(u)) } else { noise = true }
            case .word(let w):
                resolveWord(w, index: i, next: next)
            }
        }
        return out
    }

    private mutating func resolveWord(_ w: String, index i: Int, next: RawToken?) {
        let lw = w.lowercased()
        // Scale words: 5k, 2 million.
        if case .number(let n)? = out.last, w == "k" || Self.scales[lw] != nil {
            out[out.count - 1] = .number(n * (w == "k" ? 1e3 : Self.scales[lw]!)); return
        }
        // Conversion keyword: only when a unit/currency ends the line.
        if Self.conversionWords.contains(lw), !out.isEmpty, i + 2 == raw.count, let target = next,
           unitOrCurrency(target) != nil, prevEndsValue {
            out.append(.convert); return
        }
        if prevIsConvert, let u = unitOrCurrency(.word(w)) { out.append(.unit(u)); return }
        if prevIsNumber {
            // "in" means inches only when no word follows ("20 in + 3" but not "1200 in March").
            let blockedInch: Bool = {
                guard lw == "in" else { return false }
                switch next {
                case .word(let w2)?: return !Self.conversionWords.contains(w2.lowercased())
                case .variable?: return true
                default: return false
                }
            }()
            if !blockedInch, let u = unitOrCurrency(.word(w)) { out.append(.unit(u)); return }
        }
        // Currency code before the amount: "USD 20".
        if w.count >= 3, w == w.uppercased(), CurrencyCatalog.isKnown(w), case .number? = next {
            out.append(.prefix(context.currency(w))); return
        }
        if MathLexer.functions.contains(lw), startsOperand(next) { out.append(.function(lw)); return }
        switch lw {
        case "pi": out.append(.value(Quantity(.pi))); return
        case "tau": out.append(.value(Quantity(2 * .pi))); return
        case "e": out.append(.value(Quantity(M_E))); return
        default: break
        }
        if context.answerWords.contains(lw) {
            out.append(context.answer.map(Token.value) ?? .missingAnswer); return
        }
        if ["x", "times", "plus", "minus", "mod"].contains(lw), prevEndsValue, startsOperand(next) {
            let op: Op = switch lw { case "plus": .add; case "minus": .sub; case "mod": .mod; default: .mul }
            out.append(.op(op)); return
        }
        if out.last == .percent, lw == "of" || lw == "off" { out.append(lw == "of" ? .of : .off); return }
        noise = true
    }
}

// MARK: - Parsing

private struct Parser {
    let tokens: [Token]
    let context: MathContext
    var pos = 0
    var operations = 0

    init(tokens: [Token], context: MathContext) { self.tokens = tokens; self.context = context }

    var atEnd: Bool { pos >= tokens.count }
    private func peek(_ k: Int = 0) -> Token? { pos + k < tokens.count ? tokens[pos + k] : nil }

    mutating func parseExpression() throws -> Quantity {
        var q = try parseAdditive()
        if peek() == .convert {
            pos += 1
            guard case .unit(let target)? = peek() else { throw MathError.syntax }
            pos += 1
            operations += 1
            q = try MathEvaluator.convert(q, to: target)
        }
        return q
    }

    private mutating func parseAdditive() throws -> Quantity {
        var lhs = try parseMultiplicative()
        while case .op(let op)? = peek(), op == .add || op == .sub {
            pos += 1
            let rhs = try parseMultiplicative()
            lhs = try MathEvaluator.add(lhs, rhs, subtract: op == .sub)
            operations += 1
        }
        return lhs
    }

    private mutating func parseMultiplicative() throws -> Quantity {
        var lhs = try parseUnary()
        while let t = peek() {
            switch t {
            case .op(let op) where op == .mul || op == .div || op == .mod:
                pos += 1
                let rhs = try parseUnary()
                lhs = try op == .mul ? MathEvaluator.multiply(lhs, rhs)
                    : op == .div ? MathEvaluator.divide(lhs, rhs) : MathEvaluator.modulo(lhs, rhs)
            case .lparen, .function, .value:
                // Implicit multiplication: 2(3 + 4), 2pi, 3 guests.
                let rhs = try parseUnary()
                lhs = try MathEvaluator.multiply(lhs, rhs)
            default:
                return lhs
            }
            operations += 1
        }
        return lhs
    }

    private mutating func parseUnary() throws -> Quantity {
        if case .op(let op)? = peek(), op == .sub || op == .add {
            pos += 1
            var q = try parseUnary()
            if op == .sub { q.value = -q.value }
            return q
        }
        return try parsePower()
    }

    private mutating func parsePower() throws -> Quantity {
        let base = try parsePostfix()
        if peek() == .op(.pow) {
            pos += 1
            let exponent = try parseUnary()
            operations += 1
            return try MathEvaluator.power(base, exponent)
        }
        return base
    }

    private mutating func parsePostfix() throws -> Quantity {
        var q = try parsePrimary()
        while peek() == .percent {
            pos += 1
            guard q.unit == nil, !q.isPercent else { throw MathError.syntax }
            q.isPercent = true
        }
        if q.isPercent, let t = peek(), t == .of || t == .off {
            pos += 1
            let whole = try parsePower()
            operations += 1
            let share = t == .of ? q.value / 100 : 1 - q.value / 100
            return Quantity(whole.value * share, whole.unit, percent: whole.isPercent)
        }
        return q
    }

    private mutating func parsePrimary() throws -> Quantity {
        guard let t = peek() else { throw MathError.syntax }
        pos += 1
        switch t {
        case .number(let n):
            var q = Quantity(n)
            guard case .unit(let u)? = peek() else { return q }
            pos += 1
            q.unit = u
            // Adjacent quantities of one dimension add up: 5 ft 3 in, 1h 30min.
            while !u.isCurrency, case .number(let n2)? = peek(), case .unit(let u2)? = peek(1),
                  u2.dimension == u.dimension {
                pos += 2
                q = try MathEvaluator.add(q, Quantity(n2, u2), subtract: false)
                operations += 1
            }
            return q
        case .prefix(var u):
            var negative = false
            if peek() == .op(.sub) { pos += 1; negative = true }
            guard case .number(let n)? = peek() else { throw MathError.syntax }
            pos += 1
            if case .unit(let code)? = peek(), code.isCurrency { pos += 1; u = code }
            return Quantity(negative ? -n : n, u)
        case .lparen:
            let q = try parseExpression()
            if peek() == .rparen { pos += 1 } else if !atEnd { throw MathError.syntax }
            return q
        case .function(let name):
            var args: [Quantity] = []
            if peek() == .lparen {
                pos += 1
                if peek() != .rparen {
                    args.append(try parseExpression())
                    while peek() == .comma { pos += 1; args.append(try parseExpression()) }
                }
                if peek() == .rparen { pos += 1 } else if !atEnd { throw MathError.syntax }
            } else {
                args.append(try parsePower())
            }
            operations += 1
            return try MathEvaluator.apply(name, args)
        case .value(let q):
            return q
        case .missingAnswer:
            throw MathError.noPreviousAnswer
        default:
            throw MathError.syntax
        }
    }
}
