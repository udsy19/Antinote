import Foundation
import SuperNotesCore

/// Analyses notes for display (math results, sums, counts) and provides the shared text helpers.
/// Thread-safe; results are cached per note text and per math line.
public final class NoteEngine: NoteAnalyzing, @unchecked Sendable {
    private let settingsSource: () -> MathSettings
    private let ratesSource: () -> ExchangeRates
    private let lock = NSLock()
    private var lastNote: (text: String, key: NoteKey, analysis: NoteAnalysis)?
    private var lineCache: [LineKey: LineOutcome] = [:]

    /// - Parameters: sources are read once per analysis; tests inject fixed settings and rates.
    public init(settings: @escaping () -> MathSettings = { MathSettings.current },
                rates: @escaping () -> ExchangeRates = { RatesProvider.shared.current }) {
        settingsSource = settings
        ratesSource = rates
    }

    // MARK: - NoteAnalyzing

    public func analyze(_ text: String) -> NoteAnalysis {
        let lines = text.components(separatedBy: "\n")
        let detected = NoteMode.detect(firstLine: lines.first ?? "")
        let body = Array(lines.dropFirst())
        switch detected.mode {
        case .math, .sum, .average:
            let settings = settingsSource()
            let rates = ratesSource()
            let key = NoteKey(settings: settings, ratesVersion: rates.version, keyword: detected.keyword)
            lock.lock(); defer { lock.unlock() }
            if let last = lastNote, last.text == text, last.key == key { return last.analysis }
            var analysis = NoteAnalysis(mode: detected.mode, arguments: detected.arguments)
            if detected.mode == .math {
                (analysis.annotations, analysis.definitions) = analyzeMath(body, context: MathContext(settings: settings, rates: rates))
            } else {
                analysis.summary = Tally.numbers(body, average: detected.mode == .average, settings: settings, rates: rates)
            }
            lastNote = (text, key, analysis)
            return analysis
        case .count:
            return NoteAnalysis(mode: .count, arguments: detected.arguments, summary: Tally.count(body))
        case .timer:
            var analysis = NoteAnalysis(mode: .timer, arguments: detected.arguments)
            if case .failure(let error) = TimerSpec.parse(lines.first ?? "") {
                analysis.annotations = [LineAnnotation(line: 0, text: error.message, kind: .error)]
            }
            return analysis
        default:
            return NoteAnalysis(mode: detected.mode, arguments: detected.arguments)
        }
    }

    public func evaluate(_ expression: String) -> Result<Double, Error> {
        var text = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("=") { text.removeLast() }
        let context = MathContext(settings: settingsSource(), rates: ratesSource())
        switch MathEvaluator.evaluate(text, context: context) {
        case .success(let evaluation): return .success(evaluation.quantity.value)
        case .failure(let failure): return .failure(failure.error)
        }
    }

    /// Evaluates an expression and formats the result like a math note would ("$90.00", "30.48 cm").
    public func evaluateFormatted(_ expression: String) -> Result<String, Error> {
        let settings = settingsSource()
        let context = MathContext(settings: settings, rates: ratesSource())
        switch MathEvaluator.evaluate(expression, context: context) {
        case .success(let evaluation): return .success(MathFormatter(settings: settings).format(evaluation.quantity))
        case .failure(let failure): return .failure(failure.error)
        }
    }

    public func cleanPaste(_ text: String) -> String {
        PasteCleaner.clean(text, options: .current)
    }

    public func shorten(url: String) -> String {
        LinkShortener.shorten(url)
    }

    // MARK: - Math notes

    private struct NoteKey: Equatable {
        var settings: MathSettings
        var ratesVersion: Int
        var keyword: String
    }

    private struct LineKey: Hashable {
        var line: String
        var variables: [String: Quantity]
        var answer: Quantity?
        var settings: MathSettings
        var ratesVersion: Int
    }

    private struct LineOutcome {
        var annotation: (text: String, kind: LineAnnotation.Kind)?
        /// The line's value (shown or not).
        var value: Quantity?
        var definition: (name: String, value: Quantity)?
        /// Counts toward a following `total` line.
        var countsInTotal = false
        /// Becomes the previous answer.
        var isAnswer = false
    }

    private static let totalWords: Set<String> = ["total", "sum", "subtotal"]
    private static let averageWords: Set<String> = ["average", "avg", "mean"]

    /// Must be called with `lock` held. `lines` excludes the keyword line (annotation indices are offset by 1).
    /// Returns the annotations and the variable each line defines.
    private func analyzeMath(_ lines: [String], context base: MathContext) -> ([LineAnnotation], [Int: String]) {
        if lineCache.count > 5000 { lineCache.removeAll() }
        let formatter = MathFormatter(settings: base.settings)
        var context = base
        var block: [Quantity] = []
        var annotations: [LineAnnotation] = []
        var definitions: [Int: String] = [:]
        for (offset, line) in lines.enumerated() {
            let index = offset + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { block.removeAll(); continue }
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") { continue }

            var word = trimmed.lowercased()
            while let last = word.last, last == ":" || last == "=" || last == " " { word.removeLast() }
            if Self.totalWords.contains(word) || Self.averageWords.contains(word) {
                if let total = Self.total(block, average: Self.averageWords.contains(word)) {
                    annotations.append(LineAnnotation(line: index, text: formatter.format(total), value: total.value))
                    context.answer = total
                }
                block.removeAll()
                continue
            }

            let key = LineKey(line: line, variables: context.variables, answer: context.answer,
                              settings: context.settings, ratesVersion: context.rates.version)
            let outcome: LineOutcome
            if let cached = lineCache[key] { outcome = cached } else {
                outcome = Self.evaluateLine(trimmed, context: context, formatter: formatter)
                lineCache[key] = outcome
            }
            if let def = outcome.definition {
                context.variables[def.name] = def.value
                definitions[index] = def.name
            }
            if let value = outcome.value {
                if outcome.isAnswer { context.answer = value }
                if outcome.countsInTotal { block.append(value) }
            }
            if let (text, kind) = outcome.annotation {
                annotations.append(LineAnnotation(line: index, text: text, kind: kind,
                                                  value: kind == .error ? nil : outcome.value?.value))
            }
        }
        return (annotations, definitions)
    }

    private static func total(_ values: [Quantity], average: Bool) -> Quantity? {
        guard var sum = values.first else { return nil }
        var count = 1.0
        for q in values.dropFirst() {
            guard let next = try? MathEvaluator.add(sum, q, subtract: false) else { continue }
            sum = next; count += 1
        }
        if average { sum.value /= count }
        return sum
    }

    private static func evaluateLine(_ line: String, context: MathContext, formatter: MathFormatter) -> LineOutcome {
        var text = line
        var strict = false
        while text.hasSuffix("=") || text.hasSuffix(" ") {
            if text.hasSuffix("=") { strict = true }
            text.removeLast()
        }
        if let def = definition(in: text, context: context) {
            switch MathEvaluator.evaluate(def.expression, context: context) {
            case .success(let e):
                if context.variables[def.name] != nil {
                    guard !e.hadNoise || strict else { return LineOutcome() }
                    return LineOutcome(annotation: (MathError.alreadyDefined.localizedDescription, .error))
                }
                let shown = strict || e.operations > 0
                return LineOutcome(annotation: shown ? (formatter.format(e.quantity), .result) : nil, value: e.quantity,
                                   definition: (def.name, e.quantity),
                                   countsInTotal: shown && !e.quantity.isPercent, isAnswer: shown)
            case .failure(let f):
                if strict || def.strict { return LineOutcome(annotation: (f.error.localizedDescription, .error)) }
                return LineOutcome()
            }
        }
        // "2 + 2 = 4": evaluate what precedes the first "=".
        if let eq = text.firstIndex(of: "=") {
            text = String(text[..<eq])
            strict = true
        }
        switch MathEvaluator.evaluate(text, context: context) {
        case .success(var e):
            if strict, e.isLoneLiteral, let unit = e.quantity.unit, unit.isCurrency {
                // "$23 =" converts primary → secondary; any other currency → primary.
                let primary = context.settings.primaryCurrency
                let target = unit.id == primary ? context.settings.secondaryCurrency : primary
                switch Result(catching: { try MathEvaluator.convert(e.quantity, to: context.currency(target)) }) {
                case .success(let q): e.quantity = q
                case .failure(let error):
                    return LineOutcome(annotation: ((error as? MathError ?? .syntax).localizedDescription, .error))
                }
            }
            let shown = strict || e.operations > 0
            return LineOutcome(annotation: shown ? (formatter.format(e.quantity), .result) : nil, value: e.quantity,
                               countsInTotal: !e.quantity.isPercent, isAnswer: shown)
        case .failure(let f):
            let clear = strict || (f.error.isSemantic && !f.hadNoise && f.hasNumber)
            return LineOutcome(annotation: clear ? (f.error.localizedDescription, .error) : nil)
        }
    }

    private static let reservedNames: Set<String> = MathLexer.functions
        .union(["pi", "e", "tau", "ans", "prev"]).union(totalWords).union(averageWords)

    /// `name: expression` or `name = expression` with a name that starts with a letter.
    private static func definition(in text: String, context: MathContext) -> (name: String, expression: String, strict: Bool)? {
        guard let sep = text.firstIndex(where: { $0 == ":" || $0 == "=" }) else { return nil }
        let rawName = text[..<sep].trimmingCharacters(in: .whitespaces)
        var rest = text[text.index(after: sep)...]
        if text[sep] == ":", rest.hasPrefix("//") { return nil }        // URLs
        if text[sep] == ":", sep > text.startIndex, text[text.index(before: sep)].isASCIIDigit,
           rest.first?.isASCIIDigit == true { return nil }               // times of day: "at 10:30"
        var strict = false
        if text[sep] == ":", let eq = rest.firstIndex(of: "=") {         // "total cost: a + b = 12"
            rest = rest[..<eq]; strict = true
        }
        let expression = rest.trimmingCharacters(in: .whitespaces)
        guard let first = rawName.first, first.isLetter, rawName.count <= 40, !expression.isEmpty,
              rawName.allSatisfy({ $0.isLetter || $0.isNumber || $0 == " " || $0 == "_" || $0 == "-" || $0 == "'" })
        else { return nil }
        let name = rawName.lowercased().split(separator: " ").joined(separator: " ")
        guard name.split(separator: " ").count <= 5, !reservedNames.contains(name),
              !context.answerWords.contains(name) else { return nil }
        return (name, expression, strict)
    }
}
