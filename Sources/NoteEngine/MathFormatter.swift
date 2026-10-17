import Foundation
import JotterCore

/// Settings that affect math results, captured once per analysis.
public struct MathSettings: Hashable, Sendable {
    public var primaryCurrency: String
    public var secondaryCurrency: String
    public var significantDigits: Int
    /// Fixed decimal places for results, or nil for automatic (significant digits, trailing zeros trimmed).
    public var decimalPlaces: Int?
    /// Whether results in the primary currency carry its symbol.
    public var showPrimarySymbol: Bool
    public var useGrouping: Bool
    public var answerWord: String
    public var decimalSeparator: String
    public var groupingSeparator: String

    public init(primaryCurrency: String = "USD", secondaryCurrency: String = "EUR", significantDigits: Int = 6,
                decimalPlaces: Int? = nil, showPrimarySymbol: Bool = true,
                useGrouping: Bool = true, answerWord: String = "ans", decimalSeparator: String = ".",
                groupingSeparator: String = ",") {
        self.decimalPlaces = decimalPlaces; self.showPrimarySymbol = showPrimarySymbol
        self.primaryCurrency = primaryCurrency.uppercased(); self.secondaryCurrency = secondaryCurrency.uppercased()
        self.significantDigits = significantDigits; self.useGrouping = useGrouping; self.answerWord = answerWord
        self.decimalSeparator = decimalSeparator; self.groupingSeparator = groupingSeparator
    }

    /// The user's current preferences and locale.
    public static var current: MathSettings {
        let locale = Locale.current
        return MathSettings(primaryCurrency: Defaults[.primaryCurrency], secondaryCurrency: Defaults[.secondaryCurrency],
                            decimalPlaces: Defaults[.decimalPlaces] < 0 ? nil : min(Defaults[.decimalPlaces], 7),
                            showPrimarySymbol: Defaults[.showCurrencySymbol],
                            useGrouping: Defaults[.thousandsSeparator], answerWord: Defaults[.answerWord],
                            decimalSeparator: locale.decimalSeparator ?? ".",
                            groupingSeparator: locale.groupingSeparator ?? ",")
    }
}

struct MathFormatter {
    let settings: MathSettings

    func format(_ q: Quantity) -> String {
        if q.isPercent { return number(q.value) + "%" }
        guard let unit = q.unit else { return number(q.value) }
        if unit.isCurrency { return currency(q.value, code: unit.id) }
        let text = number(q.value)
        let label = unit.label(for: q.value)
        return label.hasPrefix("°") ? text + label : text + " " + label
    }

    func currency(_ value: Double, code: String) -> String {
        let amount: String
        if CurrencyCatalog.crypto[code] != nil || (value != 0 && Swift.abs(value) < 0.01) {
            amount = number(Swift.abs(value))
        } else {
            amount = number(Swift.abs(value), fractionDigits: CurrencyCatalog.zeroDecimal.contains(code) ? 0 : (settings.decimalPlaces ?? 2))
        }
        let sign = value < 0 ? "-" : ""
        if code == settings.primaryCurrency, !settings.showPrimarySymbol { return sign + amount }
        if let symbol = CurrencyCatalog.symbol(for: code, primary: settings.primaryCurrency) {
            return sign + symbol + amount
        }
        return sign + amount + " " + code
    }

    /// Rounds to the significant-digit setting (whole parts are kept), trims trailing zeros, groups thousands.
    /// `fractionDigits` forces a fixed number of decimals instead.
    func number(_ v: Double, fractionDigits: Int? = nil) -> String {
        guard v.isFinite else { return v.isNaN ? "NaN" : (v < 0 ? "-∞" : "∞") }
        let sig = max(1, settings.significantDigits)
        let magnitude = v == 0 ? 1 : Int(floor(log10(Swift.abs(v)))) + 1
        if fractionDigits == nil, v != 0, Swift.abs(v) >= 1e15 || Swift.abs(v) < 1e-9 {
            var s = String(format: "%.\(sig - 1)e", v)   // 1.23457e+20
            if let e = s.firstIndex(of: "e") {
                var mantissa = String(s[..<e])
                var exponent = String(s[s.index(after: e)...])
                if mantissa.contains(".") {
                    while mantissa.hasSuffix("0") { mantissa.removeLast() }
                    if mantissa.hasSuffix(".") { mantissa.removeLast() }
                }
                if exponent.hasPrefix("+") { exponent.removeFirst() }
                s = mantissa.replacingOccurrences(of: ".", with: settings.decimalSeparator) + "e" + exponent
            }
            return s
        }
        let fixed = fractionDigits ?? settings.decimalPlaces
        let digits = fixed ?? min(12, max(0, sig - magnitude))
        // Round half away from zero (2.5 → 3) rather than printf's half-to-even.
        let scale = pow(10, Double(digits))
        let rounded = (v * scale).rounded(.toNearestOrAwayFromZero) / scale
        var s = String(format: "%.\(digits)f", rounded.isFinite ? rounded : v)
        if fixed == nil, s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        if s == "-0" { s = "0" }
        let negative = s.hasPrefix("-")
        if negative { s.removeFirst() }
        let parts = s.split(separator: ".", maxSplits: 1).map(String.init)
        var whole = parts[0]
        if settings.useGrouping, whole.count > 3 {
            var grouped = ""
            for (i, ch) in whole.enumerated() {
                if i > 0, (whole.count - i) % 3 == 0 { grouped += settings.groupingSeparator }
                grouped.append(ch)
            }
            whole = grouped
        }
        let result = parts.count > 1 ? whole + settings.decimalSeparator + parts[1] : whole
        return negative ? "-" + result : result
    }
}
