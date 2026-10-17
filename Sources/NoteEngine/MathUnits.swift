import Foundation

enum Dimension: String, Hashable {
    case length, mass, volume, area, temperature, time, data, speed, angle, currency
}

/// A unit of measure. `factor`/`offset` map a value to the dimension's base unit (m, kg, L, m², K, s, byte, m/s,
/// rad, USD): `base = value * factor + offset`. Currencies use USD per unit; 0 means "no rate known".
struct MathUnit: Hashable {
    let id: String
    let dimension: Dimension
    let factor: Double
    var offset: Double = 0
    /// Plural label for word units ("days", "acres"); nil = `id` is used for every value.
    var plural: String? = nil

    var isCurrency: Bool { dimension == .currency }
    func toBase(_ v: Double) -> Double { v * factor + offset }
    func fromBase(_ b: Double) -> Double { (b - offset) / factor }
    func label(for value: Double) -> String { value == 1 ? id : (plural ?? id) }

    static func currency(_ code: String, usdPerUnit: Double?) -> MathUnit {
        MathUnit(id: code, dimension: .currency, factor: usdPerUnit ?? 0)
    }
}

enum UnitCatalog {
    private struct Tables {
        /// Lower-cased single-word aliases.
        var words: [String: MathUnit] = [:]
        /// Aliases that only match with exact case ("B" byte, "b" bit, "K" kelvin, "C", "F", "L").
        var exact: [String: MathUnit] = [:]
        /// Lower-cased aliases containing spaces or symbols ("fl oz", "km/h", "°c", "'").
        var phrases: [String: MathUnit] = [:]
        var byID: [String: MathUnit] = [:]

        mutating func add(_ id: String, _ dim: Dimension, _ factor: Double, offset: Double = 0, plural: String? = nil,
                          _ aliases: [String], exact exactAliases: [String] = []) {
            let unit = MathUnit(id: id, dimension: dim, factor: factor, offset: offset, plural: plural)
            byID[id] = unit
            // A single capital letter ("K") must keep its case: "k" means thousand.
            let idIsExact = id.count == 1 && id.first!.isUppercase
            for alias in idIsExact ? aliases : aliases + [id] {
                let key = alias.lowercased()
                if key.contains(where: { !$0.isLetter }) { phrases[key] = unit } else { words[key] = unit }
            }
            for alias in exactAliases + (idIsExact ? [id] : []) { exact[alias] = unit }
        }
    }

    private static let tables: Tables = {
        var t = Tables()
        populate(&t)
        return t
    }()

    /// Lower-cased aliases containing spaces or symbols, for the lexer's phrase matching.
    static var phrases: [String: MathUnit] { tables.phrases }

    static func lookup(_ word: String) -> MathUnit? {
        tables.exact[word] ?? tables.words[word.lowercased()] ?? tables.phrases[word.lowercased()]
    }

    /// The area unit made by multiplying two lengths of `lengthID` ("ft" → "ft²").
    static func area(for lengthID: String) -> MathUnit {
        tables.byID[lengthID + "²"] ?? tables.byID["m²"]!
    }

    /// The speed unit for `length ÷ time`, when one is named for that pair.
    static func speed(length: String, time: String) -> MathUnit {
        let id = switch (length, time) {
        case ("km", "h"): "km/h"
        case ("mi", "h"): "mph"
        case ("ft", "s"): "ft/s"
        case ("nmi", "h"): "kn"
        default: "m/s"
        }
        return tables.byID[id]!
    }

    private static func populate(_ t: inout Tables) {
        // Length (m)
        t.add("nm", .length, 1e-9, ["nanometer", "nanometers", "nanometre", "nanometres"])
        t.add("µm", .length, 1e-6, ["um", "micrometer", "micrometers", "micron", "microns"])
        t.add("mm", .length, 0.001, ["millimeter", "millimeters", "millimetre", "millimetres"])
        t.add("cm", .length, 0.01, ["centimeter", "centimeters", "centimetre", "centimetres"])
        t.add("m", .length, 1, ["meter", "meters", "metre", "metres"])
        t.add("km", .length, 1000, ["kms", "kilometer", "kilometers", "kilometre", "kilometres"])
        t.add("in", .length, 0.0254, ["inch", "inches", "\"", "″", "”"])
        t.add("ft", .length, 0.3048, ["foot", "feet", "'", "′", "’"])
        t.add("yd", .length, 0.9144, ["yds", "yard", "yards"])
        t.add("mi", .length, 1609.344, ["mile", "miles"])
        t.add("nmi", .length, 1852, ["nautical mile", "nautical miles"])
        t.add("ly", .length, 9.4607304725808e15, ["light year", "light years", "lightyear", "lightyears"])
        // Mass (kg)
        t.add("µg", .mass, 1e-9, ["ug", "mcg", "microgram", "micrograms"])
        t.add("mg", .mass, 1e-6, ["milligram", "milligrams"])
        t.add("g", .mass, 0.001, ["gram", "grams", "gramme", "grammes"])
        t.add("kg", .mass, 1, ["kgs", "kilo", "kilos", "kilogram", "kilograms"])
        t.add("t", .mass, 1000, ["tonne", "tonnes", "metric ton", "metric tons"])
        t.add("oz", .mass, 0.028349523125, ["ounce", "ounces"])
        t.add("lb", .mass, 0.45359237, ["lbs", "pound", "pounds"])
        t.add("st", .mass, 6.35029318, ["stone", "stones"])
        t.add("ton", .mass, 907.18474, plural: "tons", ["tons", "short ton", "short tons"])
        t.add("long ton", .mass, 1016.0469088, plural: "long tons", ["long tons"])
        // Volume (L)
        t.add("ml", .volume, 0.001, ["milliliter", "milliliters", "millilitre", "millilitres"], exact: ["mL"])
        t.add("cl", .volume, 0.01, ["centiliter", "centiliters", "centilitre", "centilitres"])
        t.add("dl", .volume, 0.1, ["deciliter", "deciliters", "decilitre", "decilitres"])
        t.add("l", .volume, 1, ["liter", "liters", "litre", "litres"], exact: ["L"])
        t.add("m³", .volume, 1000, ["m3", "cubic meter", "cubic meters", "cubic metre", "cubic metres"])
        t.add("cm³", .volume, 0.001, ["cm3", "cc", "cubic centimeter", "cubic centimeters"])
        t.add("gal", .volume, 3.785411784, ["gallon", "gallons"])
        t.add("imp gal", .volume, 4.54609, ["imperial gallon", "imperial gallons", "uk gallon", "uk gallons"])
        t.add("qt", .volume, 0.946352946, ["quart", "quarts"])
        t.add("pt", .volume, 0.473176473, ["pint", "pints"])
        t.add("cup", .volume, 0.2365882365, plural: "cups", ["cups"])
        t.add("fl oz", .volume, 0.0295735295625, ["floz", "fluid ounce", "fluid ounces"])
        t.add("tbsp", .volume, 0.01478676478125, ["tablespoon", "tablespoons"])
        t.add("tsp", .volume, 0.00492892159375, ["teaspoon", "teaspoons"])
        t.add("ft³", .volume, 28.316846592, ["ft3", "cubic foot", "cubic feet"])
        t.add("in³", .volume, 0.016387064, ["in3", "cubic inch", "cubic inches"])
        // Area (m²)
        t.add("mm²", .area, 1e-6, ["mm2", "sqmm", "sq mm", "square millimeter", "square millimeters"])
        t.add("cm²", .area, 1e-4, ["cm2", "sqcm", "sq cm", "square centimeter", "square centimeters"])
        t.add("m²", .area, 1, ["m2", "sqm", "sq m", "square meter", "square meters", "square metre", "square metres"])
        t.add("km²", .area, 1e6, ["km2", "sqkm", "sq km", "square kilometer", "square kilometers"])
        t.add("ha", .area, 1e4, ["hectare", "hectares"])
        t.add("acre", .area, 4046.8564224, plural: "acres", ["acres", "ac"])
        t.add("in²", .area, 0.00064516, ["in2", "sqin", "sq in", "square inch", "square inches"])
        t.add("ft²", .area, 0.09290304, ["ft2", "sqft", "sq ft", "square foot", "square feet"])
        t.add("yd²", .area, 0.83612736, ["yd2", "sqyd", "sq yd", "square yard", "square yards"])
        t.add("mi²", .area, 2589988.110336, ["mi2", "sqmi", "sq mi", "square mile", "square miles"])
        // Temperature (K)
        t.add("°C", .temperature, 1, offset: 273.15, ["celsius", "degc", "degrees celsius"], exact: ["C"])
        t.add("°F", .temperature, 5.0 / 9.0, offset: 459.67 * 5.0 / 9.0, ["fahrenheit", "degf", "degrees fahrenheit"],
            exact: ["F"])
        t.add("K", .temperature, 1, ["kelvin", "kelvins"])
        // Time (s)
        t.add("ns", .time, 1e-9, ["nanosecond", "nanoseconds"])
        t.add("ms", .time, 0.001, ["millisecond", "milliseconds"])
        t.add("s", .time, 1, ["sec", "secs", "second", "seconds"])
        t.add("min", .time, 60, ["mins", "minute", "minutes"])
        t.add("h", .time, 3600, ["hr", "hrs", "hour", "hours"])
        t.add("day", .time, 86400, plural: "days", ["d", "days"])
        t.add("week", .time, 604800, plural: "weeks", ["wk", "wks", "weeks"])
        t.add("month", .time, 2629746, plural: "months", ["mo", "mos", "months"])
        t.add("year", .time, 31556952, plural: "years", ["y", "yr", "yrs", "years"])
        // Data (byte)
        t.add("bit", .data, 0.125, plural: "bits", ["bits"], exact: ["b"])
        t.add("byte", .data, 1, plural: "bytes", ["bytes"], exact: ["B"])
        t.add("KB", .data, 1e3, ["kilobyte", "kilobytes"])
        t.add("MB", .data, 1e6, ["megabyte", "megabytes"])
        t.add("GB", .data, 1e9, ["gigabyte", "gigabytes"])
        t.add("TB", .data, 1e12, ["terabyte", "terabytes"])
        t.add("PB", .data, 1e15, ["petabyte", "petabytes"])
        t.add("KiB", .data, 1024, ["kibibyte", "kibibytes"])
        t.add("MiB", .data, 1_048_576, ["mebibyte", "mebibytes"])
        t.add("GiB", .data, 1_073_741_824, ["gibibyte", "gibibytes"])
        t.add("TiB", .data, 1_099_511_627_776, ["tebibyte", "tebibytes"])
        t.add("Mbit", .data, 125_000, ["megabit", "megabits"])
        t.add("Gbit", .data, 125_000_000, ["gigabit", "gigabits"])
        // Speed (m/s)
        t.add("m/s", .speed, 1, ["mps", "meters per second"])
        t.add("km/h", .speed, 1 / 3.6, ["kmh", "kph", "kmph", "kilometers per hour"])
        t.add("mph", .speed, 0.44704, ["mi/h", "miles per hour"])
        t.add("kn", .speed, 1852.0 / 3600.0, ["kt", "knot", "knots"])
        t.add("ft/s", .speed, 0.3048, ["fps"])
        // Angle (rad)
        t.add("rad", .angle, 1, ["radian", "radians"])
        t.add("°", .angle, Double.pi / 180, ["deg", "degree", "degrees"])
    }
}

enum CurrencyCatalog {
    static let fiat: Set<String> = Set("""
    AED AFN ALL AMD ANG AOA ARS AUD AWG AZN BAM BBD BDT BGN BHD BIF BMD BND BOB BRL BSD BTN BWP BYN BZD CAD CDF CHF \
    CLP CNY COP CRC CUP CVE CZK DJF DKK DOP DZD EGP ERN ETB EUR FJD FKP GBP GEL GHS GIP GMD GNF GTQ GYD HKD HNL HTG \
    HUF IDR ILS INR IQD IRR ISK JMD JOD JPY KES KGS KHR KMF KRW KWD KYD KZT LAK LBP LKR LRD LSL LYD MAD MDL MGA MKD \
    MMK MNT MOP MRU MUR MVR MWK MXN MYR MZN NAD NGN NIO NOK NPR NZD OMR PAB PEN PGK PHP PKR PLN PYG QAR RON RSD RUB \
    RWF SAR SBD SCR SDG SEK SGD SHP SLE SOS SRD SSP STN SYP SZL THB TJS TMT TND TOP TRY TTD TWD TZS UAH UGX USD UYU \
    UZS VES VND VUV WST XAF XCD XOF XPF YER ZAR ZMW ZWL
    """.split(separator: " ").map(String.init))

    /// Crypto code → CoinGecko id.
    static let crypto: [String: String] = [
        "BTC": "bitcoin", "ETH": "ethereum", "SOL": "solana", "DOGE": "dogecoin", "ADA": "cardano", "XRP": "ripple",
        "DOT": "polkadot", "LTC": "litecoin", "BNB": "binancecoin", "USDT": "tether", "USDC": "usd-coin",
        "AVAX": "avalanche-2", "LINK": "chainlink", "SHIB": "shiba-inu", "TRX": "tron", "ATOM": "cosmos",
        "XLM": "stellar", "NEAR": "near", "PEPE": "pepe", "TON": "the-open-network", "BCH": "bitcoin-cash",
        "XMR": "monero", "ALGO": "algorand", "POL": "polygon-ecosystem-token", "ETC": "ethereum-classic",
        "UNI": "uniswap", "AAVE": "aave", "ARB": "arbitrum", "OP": "optimism", "SUI": "sui", "APT": "aptos",
        "HBAR": "hedera-hashgraph", "FIL": "filecoin", "DAI": "dai",
    ]

    /// Codes also recognised in lower case ("20 eur").
    private static let lowercaseCodes: Set<String> = [
        "usd", "eur", "gbp", "jpy", "cad", "aud", "chf", "cny", "inr", "nzd", "sek", "nok", "dkk", "mxn", "brl",
        "krw", "sgd", "hkd", "zar", "rub", "pln", "btc", "eth", "sol", "doge", "xrp", "ada", "ltc",
    ]
    private static let names: [String: String] = [
        "euro": "EUR", "euros": "EUR", "yen": "JPY", "rupee": "INR", "rupees": "INR", "yuan": "CNY", "rmb": "CNY",
        "ruble": "RUB", "rubles": "RUB", "roubles": "RUB", "bitcoin": "BTC", "bitcoins": "BTC", "ether": "ETH",
        "pesos": "MXN", "francs": "CHF", "dollar": "$", "dollars": "$", "bucks": "$",
    ]
    /// Dollar currencies: `$` means the primary currency when it is one of these.
    static let dollarFamily: Set<String> = ["USD", "CAD", "AUD", "NZD", "HKD", "SGD", "MXN", "TWD", "ARS", "CLP", "COP"]
    static let zeroDecimal: Set<String> = ["JPY", "KRW", "VND", "CLP", "ISK", "UGX", "PYG"]

    /// Symbol → code; "$" and "¥" are resolved against the primary currency.
    static let symbols: [String: String] = [
        "$": "$", "€": "EUR", "£": "GBP", "¥": "¥", "₹": "INR", "₩": "KRW", "₽": "RUB", "₺": "TRY", "₫": "VND",
        "₱": "PHP", "₪": "ILS", "₴": "UAH", "₦": "NGN", "฿": "THB", "₿": "BTC", "₡": "CRC", "₸": "KZT", "₼": "AZN",
        "₾": "GEL", "₲": "PYG", "₵": "GHS", "₭": "LAK", "₮": "MNT",
        "us$": "USD", "ca$": "CAD", "c$": "CAD", "au$": "AUD", "a$": "AUD", "nz$": "NZD", "hk$": "HKD", "s$": "SGD",
        "r$": "BRL", "mx$": "MXN", "nt$": "TWD",
    ]
    private static let displaySymbols: [String: String] = [
        "EUR": "€", "GBP": "£", "JPY": "¥", "CNY": "CN¥", "INR": "₹", "KRW": "₩", "RUB": "₽", "TRY": "₺", "VND": "₫",
        "PHP": "₱", "ILS": "₪", "UAH": "₴", "NGN": "₦", "THB": "฿", "CAD": "CA$", "AUD": "A$", "NZD": "NZ$",
        "HKD": "HK$", "SGD": "S$", "BRL": "R$", "MXN": "MX$", "TWD": "NT$",
    ]
    private static let primarySymbols: [String: String] = ["CNY": "¥", "CAD": "$", "AUD": "$", "NZD": "$",
                                                           "HKD": "$", "SGD": "$", "MXN": "$", "TWD": "$"]

    static func isKnown(_ code: String) -> Bool { fiat.contains(code) || crypto[code] != nil }

    /// Resolves the placeholder codes "$" / "¥" against the primary currency.
    static func resolve(_ code: String, primary: String) -> String {
        switch code {
        case "$": dollarFamily.contains(primary) ? primary : "USD"
        case "¥": primary == "CNY" ? "CNY" : "JPY"
        default: code
        }
    }

    /// The currency a word names: an upper-case ISO/crypto code, a common lower-case code, or a name.
    static func code(forWord word: String, primary: String) -> String? {
        if word.count >= 3, word == word.uppercased(), isKnown(word) { return word }
        let lower = word.lowercased()
        if lowercaseCodes.contains(lower) { return lower.uppercased() }
        return names[lower].map { resolve($0, primary: primary) }
    }

    /// Prefix symbol used when formatting, or nil to print the code after the amount.
    static func symbol(for code: String, primary: String) -> String? {
        if code == primary { return primarySymbols[code] ?? (code == "USD" ? "$" : displaySymbols[code]) }
        if code == "USD" { return dollarFamily.contains(primary) ? "US$" : "$" }
        return displaySymbols[code]
    }
}
