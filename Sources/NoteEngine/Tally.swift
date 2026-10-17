import Foundation

/// Sum, average and count notes.
enum Tally {
    struct Found: Equatable {
        var value: Double
        /// Currency code, when a symbol or code sits next to the number.
        var currency: String?
    }

    /// Every number in `line` that stands on its own ("$4.25", "-5", "1,200", "20%"), not glued to letters.
    static func numbers(in line: String, primary: String) -> [Found] {
        let c = Array(line)
        var found: [Found] = []
        var i = 0
        while i < c.count {
            let startsNumber = c[i].isASCIIDigit || (c[i] == "." && i + 1 < c.count && c[i + 1].isASCIIDigit)
            guard startsNumber, i == 0 || !(c[i - 1].isLetter || c[i - 1].isASCIIDigit),
                  let (value, end) = NumberScanner.scan(c, at: i) else {
                // Skip the rest of a word so "abc123" contributes nothing.
                if c[i].isLetter || c[i].isASCIIDigit {
                    while i < c.count, c[i].isLetter || c[i].isASCIIDigit { i += 1 }
                } else { i += 1 }
                continue
            }
            if end < c.count, c[end].isLetter, codeAfter(c, end, primary: primary) == nil {
                i = end
                while i < c.count, c[i].isLetter || c[i].isASCIIDigit { i += 1 }
                continue
            }
            var j = i - 1
            var currency: String?
            if j >= 0, let code = CurrencyCatalog.symbols[String(c[j])] {
                currency = CurrencyCatalog.resolve(code, primary: primary); j -= 1
            }
            let negative = j >= 0 && (c[j] == "-" || c[j] == "−") && (j == 0 || !(c[j - 1].isLetter || c[j - 1].isASCIIDigit))
            if let code = codeAfter(c, end, primary: primary) { currency = code }
            found.append(Found(value: negative ? -value : value, currency: currency))
            i = end
        }
        return found
    }

    /// A currency symbol or code right after a number ("5€", "5 EUR", "5 euros").
    private static func codeAfter(_ c: [Character], _ end: Int, primary: String) -> String? {
        var k = end
        if k < c.count, c[k] == " " { k += 1 }
        guard k < c.count else { return nil }
        if let code = CurrencyCatalog.symbols[String(c[k])] { return CurrencyCatalog.resolve(code, primary: primary) }
        var w = k
        while w < c.count, c[w].isLetter { w += 1 }
        guard w > k else { return nil }
        return CurrencyCatalog.code(forWord: String(c[k..<w]), primary: primary)
    }

    /// "Total: $37.25" / "Average: 9.31".
    static func numbers(_ lines: [String], average: Bool, settings: MathSettings, rates: ExchangeRates) -> String {
        let primary = settings.primaryCurrency
        let all = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .flatMap { numbers(in: $0, primary: primary) }
        let target = all.first { $0.currency != nil }?.currency
        var total = 0.0
        for item in all {
            if let code = item.currency, let target, code != target,
               let from = rates.usdPerUnit(code), let to = rates.usdPerUnit(target) {
                total += item.value * from / to
            } else {
                total += item.value
            }
        }
        let value = average ? (all.isEmpty ? 0 : total / Double(all.count)) : total
        let formatter = MathFormatter(settings: settings)
        let text = target.map { formatter.currency(value, code: $0) } ?? formatter.number(value)
        return (average ? "Average: " : "Total: ") + text
    }

    /// "4 items · 5 lines · 8 words · 41 characters" (comment lines excluded).
    static func count(_ lines: [String]) -> String {
        let counted = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        let items = counted.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let words = counted.reduce(0) { $0 + $1.split(whereSeparator: { $0.isWhitespace }).count }
        let characters = counted.reduce(0) { $0 + $1.count }
        func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        return [plural(items, "item"), plural(counted.count, "line"), plural(words, "word"),
                plural(characters, "character")].joined(separator: " · ")
    }
}
