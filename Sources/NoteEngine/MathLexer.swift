import Foundation

enum Op: Character {
    case add = "+", sub = "-", mul = "*", div = "/", pow = "^", mod = "m"
}

/// Lexical tokens before context resolution.
enum RawToken: Equatable {
    case number(Double)
    case op(Op)
    case lparen, rparen, comma, percent
    /// A currency symbol; the code may be the placeholder "$" or "¥".
    case currencySymbol(String)
    /// A unit spelled with spaces or symbols ("fl oz", "km/h", "'").
    case unitPhrase(MathUnit)
    case variable(String)
    /// Words that are operators ("divided by", "multiplied by").
    case opPhrase(Op)
    case word(String)
}

enum NumberScanner {
    /// Scans a number starting at `start` (a digit, or "." followed by a digit). Handles thousands separators,
    /// decimal commas and scientific notation. Returns nil when there is no number.
    static func scan(_ c: [Character], at start: Int, allowComma: Bool = true) -> (value: Double, end: Int)? {
        var j = start
        var run: [Character] = []
        while j < c.count {
            let ch = c[j]
            if ch.isASCIIDigit {
                run.append(ch)
            } else if (ch == "." || (ch == "," && allowComma)), j + 1 < c.count, c[j + 1].isASCIIDigit {
                run.append(ch)
            } else {
                break
            }
            j += 1
        }
        guard !run.isEmpty, let (parsed, used) = interpret(run) else { return nil }
        var text = parsed
        var end = start + used
        // Scientific notation: 1.5e3, 2E-4 (not followed by a letter, so "5em" stays a number + word).
        if used == run.count, end < c.count, c[end] == "e" || c[end] == "E" {
            var k = end + 1
            var exp = ""
            if k < c.count, c[k] == "+" || c[k] == "-" { exp.append(c[k]); k += 1 }
            let digitsStart = k
            while k < c.count, c[k].isASCIIDigit { exp.append(c[k]); k += 1 }
            if k > digitsStart, k == c.count || !c[k].isLetter {
                text += "e" + exp
                end = k
            }
        }
        guard let value = Double(text) else { return nil }
        return (value, end)
    }

    /// Normalises a run of digits and separators into a Double literal, returning how many characters it used.
    private static func interpret(_ run: [Character]) -> (String, Int)? {
        let seps = run.indices.filter { run[$0] == "." || run[$0] == "," }
        if seps.isEmpty { return (String(run), run.count) }
        let groups = split(run)
        let chars = Set(seps.map { run[$0] })
        func grouped(_ gs: [String]) -> Bool {
            (1...3).contains(gs[0].count) && gs.dropFirst().allSatisfy { $0.count == 3 }
        }
        if chars.count == 1 {
            let sep = run[seps[0]]
            if seps.count == 1 {
                // "1,540" is thousands; "4,25" / "0,500" are decimal commas; "." is always decimal.
                if sep == ",", groups[1].count == 3, groups[0] != "0" { return (groups.joined(), run.count) }
                return (groups[0] + "." + groups[1], run.count)
            }
            if grouped(groups) { return (groups.joined(), run.count) }
            return interpret(Array(run[..<seps[1]]))
        }
        // Both separators: the last one is the decimal point ("1,234.56", "1.234,56").
        let decimal = run[seps.last!]
        let firstDecimal = seps.first { run[$0] == decimal }!
        if firstDecimal == seps.last!, grouped(Array(groups.dropLast())) {
            return (groups.dropLast().joined() + "." + groups.last!, run.count)
        }
        return interpret(Array(run[..<seps.last!]))
    }

    private static func split(_ run: [Character]) -> [String] {
        run.split(omittingEmptySubsequences: false) { $0 == "." || $0 == "," }.map { String($0) }
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    var isWordChar: Bool { isLetter || isASCIIDigit || self == "_" || self == "²" || self == "³" }
}

enum MathLexer {
    static let functions: Set<String> = [
        "sqrt", "cbrt", "abs", "round", "floor", "ceil", "sin", "cos", "tan", "asin", "acos", "atan", "log", "ln",
        "log2", "exp", "min", "max",
    ]

    private typealias Phrase = (chars: [Character], token: RawToken)

    /// Unit, currency and operator phrases by first character, longest first.
    private static let staticPhrases: [Character: [Phrase]] = {
        var list: [(String, RawToken)] = UnitCatalog.phrases.map { ($0.key, .unitPhrase($0.value)) }
        list += CurrencyCatalog.symbols.filter { $0.key.count > 1 }.map { ($0.key, .currencySymbol($0.value)) }
        list += [("divided by", .opPhrase(.div)), ("multiplied by", .opPhrase(.mul))]
        return phraseIndex(list.map { (Array($0.0), $0.1) })
    }()

    private static func phraseIndex(_ phrases: [Phrase]) -> [Character: [Phrase]] {
        Dictionary(grouping: phrases) { $0.chars[0] }.mapValues { $0.sorted { $0.chars.count > $1.chars.count } }
    }

    /// Splits `text` into raw tokens. `variables` are lower-cased names (matched longest first, before anything else).
    static func lex(_ text: String, variables: [String]) -> [RawToken] {
        let c = Array(text)
        let lower = c.map { ch -> Character in
            guard ch.isUppercase else { return ch }
            let l = ch.lowercased()
            return l.count == 1 ? Character(l) : ch
        }
        let varPhrases = phraseIndex(variables.map { (chars: Array($0), token: RawToken.variable($0)) })
        var tokens: [RawToken] = []
        // Paren stack: true when the paren opened a function call (commas separate arguments there).
        var parens: [Bool] = []
        var i = 0
        func matches(_ p: [Character]) -> Bool {
            guard i + p.count <= lower.count else { return false }
            for k in 0..<p.count where lower[i + k] != p[k] { return false }
            if p.last!.isWordChar, i + p.count < lower.count, lower[i + p.count].isWordChar { return false }
            return true
        }
        while i < c.count {
            let ch = c[i]
            if ch.isWhitespace { i += 1; continue }
            if ch.isASCIIDigit || (ch == "." && i + 1 < c.count && c[i + 1].isASCIIDigit) {
                let inFunction = parens.last ?? false
                if let (value, end) = NumberScanner.scan(c, at: i, allowComma: !inFunction) {
                    tokens.append(.number(value)); i = end; continue
                }
            }
            if let p = varPhrases[lower[i]]?.first(where: { matches($0.chars) })
                ?? staticPhrases[lower[i]]?.first(where: { matches($0.chars) }) {
                tokens.append(p.token); i += p.chars.count; continue
            }
            if let code = CurrencyCatalog.symbols[String(ch)] {
                tokens.append(.currencySymbol(code)); i += 1; continue
            }
            switch ch {
            case "+": tokens.append(.op(.add))
            case "-", "−", "–": tokens.append(.op(.sub))
            case "*" where i + 1 < c.count && c[i + 1] == "*": tokens.append(.op(.pow)); i += 1
            case "*", "×", "·", "⋅": tokens.append(.op(.mul))
            case "/", "÷": tokens.append(.op(.div))
            case "^": tokens.append(.op(.pow))
            case "%": tokens.append(.percent)
            case "(":
                let isCall: Bool
                if case .word(let w)? = tokens.last { isCall = functions.contains(w.lowercased()) } else { isCall = false }
                parens.append(isCall); tokens.append(.lparen)
            case ")": _ = parens.popLast(); tokens.append(.rparen)
            case ",": tokens.append(.comma)
            case "√": tokens.append(.word("sqrt"))
            case "π": tokens.append(.word("pi"))
            default:
                if ch.isLetter {
                    var j = i
                    while j < c.count, c[j].isWordChar { j += 1 }
                    tokens.append(.word(String(c[i..<j])))
                    i = j
                    continue
                }
                // Other punctuation (":", "!", "?", "=", quotes not after numbers…) is descriptive noise.
            }
            i += 1
        }
        return tokens
    }
}
