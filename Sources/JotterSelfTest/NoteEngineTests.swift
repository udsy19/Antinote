import Foundation
import JotterCore
import NoteEngine

private let fixedRates = ExchangeRates(perUSD: ["EUR": 0.9, "GBP": 0.8, "JPY": 150, "CAD": 1.35, "BTC": 0.00001,
                                                "ETH": 0.0005])

private func makeEngine(_ settings: MathSettings = MathSettings()) -> NoteEngine {
    NoteEngine(settings: { settings }, rates: { fixedRates })
}

/// Annotation text for `line` (1-based after the keyword) of a math note; errors are prefixed with "!".
private func math(_ body: String, line: Int = 1, engine: NoteEngine = makeEngine()) -> String? {
    let analysis = engine.analyze("math\n" + body)
    guard let a = analysis.annotations.first(where: { $0.line == line }) else { return nil }
    return a.kind == .error ? "!" + a.text : a.text
}

private func expect(_ body: String, _ expected: String?, line: Int = 1, engine: NoteEngine = makeEngine(),
                    file: String = #fileID, lineNo: Int = #line) {
    let got = math(body, line: line, engine: engine)
    check(got == expected, "math \(body.debugDescription) → \(got ?? "nil"), expected \(expected ?? "nil")",
          file: file, line: lineNo)
}

func registerNoteEngineTests() {
    SelfTest.cases.append(("NoteEngine.math.arithmetic", {
        expect("240 + (23 / 8) * 6 =", "257.25")
        expect("Rent 1200 + groceries 340", "1,540")
        expect("$4.25 for lychee + $21 for moon cakes =", "$25.25")
        expect("$4,25 for lychee + $21 for moon cakes =", "$25.25")
        expect("2^10", "1,024")
        expect("-2^2", "-4")
        expect("2 x 3", "6")
        expect("4.50 × 20", "90")
        expect("10 ÷ 4", "2.5")
        expect("7 mod 3", "1")
        expect("3 times 4 plus 1", "13")
        expect("1/3", "0.333333")
        expect("1.5e3 + 1", "1,501")
        expect("1,234,567 + 1", "1,234,568")
        expect("1.234,5 + 0,5", "1,235")
        expect("5k + 500", "5,500")
        expect("2 million / 4", "500,000")
        expect("2(3 + 4)", "14")
        expect("(1 + 2", "3")
        expect("12 =", "12")
        expect("2 + 2 = 4", "4")
        expect("1e20 * 3", "3e20")
    }))

    SelfTest.cases.append(("NoteEngine.math.percentAndFunctions", {
        expect("20% of 80", "16")
        expect("20% off 80", "64")
        expect("80 + 15%", "92")
        expect("50 - 10%", "45")
        expect("80 * 15%", "12")
        expect("5% + 3%", "8%")
        expect("$200 - 25%", "$150.00")
        expect("sqrt(16) + abs(-3)", "7")
        expect("√16 * 2", "8")
        expect("max(1, 5, 3)", "5")
        expect("min(4, 2) + 0", "2")
        expect("round(3.14159, 2) =", "3.14")
        expect("floor(2.7) + ceil(2.1)", "5")
        expect("sin(30°)", "0.5")
        expect("cos(0)", "1")
        expect("2pi", "6.28319")
        expect("log(1000)", "3")
        expect("ln(e)", "1")
        expect("sqrt(-1) =", "!Invalid argument for sqrt")
    }))

    SelfTest.cases.append(("NoteEngine.math.proseAndErrors", {
        expect("I have 3 cats and 2 dogs", nil)
        expect("Meeting at 10:30", nil)
        expect("Call mom", nil)
        expect("- buy milk", nil)
        expect("Rent 1200", nil)
        expect("5 +", nil)
        expect("5 + =", "!Invalid expression")
        expect("10 / 0", "!Division by zero")
        expect("Split 10 / 0 ways", nil)
        expect("5 kg + 3 m", "!Can't combine kg and m")
        expect("// 5 + 5", nil)
        expect("# Groceries 5 + 5", nil)
        expect("Note: https://example.com/a-1", nil)
        expect("ans + 1", nil)
        expect("ans + 1 =", "!No previous answer")
        expect("10 CHF to USD", "!No exchange rate for CHF")
    }))

    SelfTest.cases.append(("NoteEngine.math.units", {
        expect("89 miles to km =", "143.232 km")
        expect("32 oz to lbs =", "2 lb")
        expect("4\" 2' to cm =", "71.12 cm")
        expect("3 ft + 20 in in cm", "142.24 cm")
        expect("5 ft 3 in to cm", "160.02 cm")
        expect("100 F to C", "37.7778°C")
        expect("0 °C in fahrenheit", "32°F")
        expect("300 K to C", "26.85°C")
        expect("1 GB in MB", "1,000 MB")
        expect("2 h in min", "120 min")
        expect("1 day in hours", "24 h")
        expect("2 weeks in days", "14 days")
        expect("60 mph in km/h", "96.5606 km/h")
        expect("180 deg to rad", "3.14159 rad")
        expect("3 m * 4 m", "12 m²")
        expect("10 ft * 12 ft", "120 ft²")
        expect("100 km / 2 h", "50 km/h")
        expect("1 acre in sqft", "43,560 ft²")
        expect("1 cup in ml", "236.588 ml")
        expect("5 kg + 3 lb", "6.36078 kg")
        expect("2 l + 500 ml", "2.5 l")
        expect("1 mile / 1 km", "1.60934")
        expect("8 bits in bytes", "1 byte")
        expect("Walked 5 km + 2 km", "7 km")
    }))

    SelfTest.cases.append(("NoteEngine.math.currency", {
        expect("Coffee: $4.50 × 20", "$90.00")
        expect("$32 USD to JPY =", "¥4,800")
        expect("$23 =", "€20.70")
        expect("€5 =", "$5.56")
        expect("$5 BTC =", "$500,000.00")
        expect("€10 in USD", "$11.11")
        expect("100 EUR to GBP", "£88.89")
        expect("£5 + $10", "£13.00")
        expect("0.5 BTC in ETH", "25 ETH")
        expect("20 eur + 5", "€25.00")
        expect("10 euros + 5 euros", "€15.00")
        expect("-$5 + $2", "-$3.00")
        expect("$10 / 4", "$2.50")
        expect("1000 yen to usd", "$6.67")
        expect("5€ + 5€", "€10.00")
        expect("100 CAD to USD", "$74.07")
        expect("$10 * 3 to CAD", "CA$40.50")
        // Primary currency CAD: "$" means CAD and USD prints as US$.
        let cad = makeEngine(MathSettings(primaryCurrency: "CAD", secondaryCurrency: "USD"))
        expect("$27 =", "US$20.00", engine: cad)
        expect("$10 + $5", "$15.00", engine: cad)
    }))

    SelfTest.cases.append(("NoteEngine.math.variables", {
        let tutorial = "guests: 5\ncost per guest: $34\nand then you can use these variables\nguests * cost per guest ="
        expect(tutorial, nil, line: 1)
        expect(tutorial, nil, line: 2)
        expect(tutorial, nil, line: 3)
        expect(tutorial, "$170.00", line: 4)
        let engine = makeEngine()
        let chain = "hourly rate: 23.75\ndaily earnings: hourly rate * 8 =\nmonthly salary: daily earnings * 20 ="
        expect(chain, "190", line: 2, engine: engine)
        expect(chain, "3,800", line: 3, engine: engine)
        let changed = chain.replacingOccurrences(of: "23.75", with: "25")
        expect(changed, "200", line: 2, engine: engine)
        expect(changed, "4,000", line: 3, engine: engine)
        expect("tax: 8%\nprice = 50\nprice + tax", "54", line: 3)
        expect("Price = 20\nPRICE * 2", "40", line: 2)
        expect("x: 5\nx: 6", "!Already defined", line: 2)
        expect("Total: 1200 + 300", "1,500")
        expect("pizzas: 3\n2 pizzas", "6", line: 2)
        expect("rate: 1.5\nrated 10 + 2", "12", line: 2)
    }))

    SelfTest.cases.append(("NoteEngine.math.answersAndTotals", {
        expect("10 + 5\nans * 2", "30", line: 2)
        expect("10 + 5\nans * 2\nprev + 1", "31", line: 3)
        expect("Rent 1200\nFood 300 + 50\ntotal", "1,550", line: 3)
        expect("$10\n$5.50\nsum:", "$15.50", line: 3)
        expect("5\n\n7 + 1\ntotal", "8", line: 4)
        expect("4 + 0\n6 + 0\naverage", "5", line: 3)
        expect("guests: 5\n10 + 1\ntotal", "11", line: 3)
        expect("Rent 1200\nFood 300\ntotal\nans / 2", "750", line: 4)
        expect("$10\n€9\ntotal", "$20.00", line: 3)
        let custom = makeEngine(MathSettings(answerWord: "above"))
        expect("2 + 2\nabove * 10", "40", line: 2, engine: custom)
    }))

    SelfTest.cases.append(("NoteEngine.math.formatting", {
        let three = makeEngine(MathSettings(significantDigits: 3))
        expect("1/3", "0.333", engine: three)
        expect("1234.5678 + 0", "1,235", engine: three)
        let plain = makeEngine(MathSettings(useGrouping: false))
        expect("1000 * 1000", "1000000", engine: plain)
        let european = makeEngine(MathSettings(decimalSeparator: ",", groupingSeparator: "."))
        expect("1000 + 0.5", "1.000,5", engine: european)
        expect("0.000012345 * 1", "0.000012345")
        let annotation = makeEngine().analyze("math\n2 + 3").annotations.first
        check(annotation?.value == 5 && annotation?.line == 1 && annotation?.kind == .result, "annotation value and line")
    }))

    SelfTest.cases.append(("NoteEngine.sumAverageCount", {
        let engine = makeEngine()
        let tutorial = "$2 for apples, $25 for bus tickets, $6 for coffee and $4.25 for a bagel."
        check(engine.analyze("sum\n" + tutorial).summary == "Sum: $37.25", "tutorial sum")
        check(engine.analyze("avg\n" + tutorial).summary == "Average: $9.31", "tutorial average")
        check(engine.analyze("sum\n$2 for apples, $4,25 for a bagel").summary == "Sum: $6.25", "decimal comma")
        let mixed = engine.analyze("sum\n10\n// 5\n-3 and abc123 and 5kg\n1,200")
        check(mixed.summary == "Sum: 1,207", "plain numbers, comments and glued words: \(mixed.summary ?? "nil")")
        check(engine.analyze("sum\n10 EUR\n$9").summary == "Sum: €18.10", "currency conversion in sum")
        check(engine.analyze("total\nnothing here").summary == "Sum: 0", "empty sum")
        check(engine.analyze("mean\n1\n2\n3\n4").summary == "Average: 2.5", "average")
        let count = engine.analyze("count\nTed Bluderfield\nSadie Lafleur\n\n// skip me\nCarl")
        check(count.mode == .count && count.summary == "3 items · 4 lines · 5 words · 32 characters",
              "count summary: \(count.summary ?? "nil")")
        check(engine.analyze("count\none").summary == "1 item · 1 line · 1 word · 3 characters", "singulars")
    }))

    SelfTest.cases.append(("NoteEngine.modes", {
        let engine = makeEngine()
        let timer = engine.analyze("timer 25m tea\n")
        check(timer.mode == .timer && timer.arguments == "25m tea" && timer.annotations.isEmpty, "timer note")
        let bad = engine.analyze("timer 1 2 3")
        check(bad.annotations.first?.kind == .error && bad.annotations.first?.line == 0, "invalid timer flagged")
        check(engine.analyze("list\nmilk").mode == .list, "list mode")
        check(engine.analyze("hello\n2 + 2").annotations.isEmpty, "plain notes have no math")
        check(engine.analyze("").mode == .plain, "empty note")
        if case .success(let v) = engine.evaluate("2 + 3 * 4 =") { check(v == 14, "evaluate") } else { check(false, "evaluate") }
        if case .failure = engine.evaluate("hello") {} else { check(false, "evaluate fails on prose") }
        if case .success(let s) = engine.evaluateFormatted("3 ft in cm") { check(s == "91.44 cm", "evaluateFormatted") }
        else { check(false, "evaluateFormatted") }
    }))

    SelfTest.cases.append(("NoteEngine.performance", {
        let engine = makeEngine()
        var lines = ["math", "rate: 1.5"]
        for i in 0..<500 {
            switch i % 5 {
            case 0: lines.append("Item costs $\(i).50 + tax 8%")
            case 1: lines.append("\(i) km to mi")
            case 2: lines.append("rate * \(i) =")
            case 3: lines.append("Just some descriptive prose about line \(i)")
            default: lines.append("total")
            }
        }
        let note = lines.joined(separator: "\n")
        let start = Date()
        let analysis = engine.analyze(note)
        let first = Date().timeIntervalSince(start)
        check(analysis.annotations.count == 400, "500-line note annotated (\(analysis.annotations.count))")
        let editStart = Date()
        _ = engine.analyze(note + "\n1 + 1")
        let edit = Date().timeIntervalSince(editStart)
        print("  NoteEngine: 500 lines in \(Int(first * 1000)) ms, re-analysis after edit \(Int(edit * 1000)) ms")
        check(first < 0.5 && edit < 0.1, "analysis is fast")
    }))

    SelfTest.cases.append(("NoteEngine.lists", {
        let box = ListLine.parse("[ ] buy milk")
        check(box.marker == .checkbox(checked: false) && box.text == "buy milk" && box.level == 0, "checkbox")
        let done = ListLine.parse("\t- [x] done")
        check(done.marker == .checkbox(checked: true, dashed: true) && done.level == 1 && done.isChecked, "dashed task")
        check(done.formatted == "\t- [x] done" && done.prefixLength == 7, "round trip")
        check(ListLine.parse("        * item").marker == .bullet("*") && ListLine.parse("        * item").level == 2, "indent")
        check(ListLine.parse("• dot").marker == .bullet("•"), "bullet dot")
        check(ListLine.parse("12. step").marker == .numbered(12), "numbered")
        check(ListLine.parse("3) x").marker == .numbered(3, delimiter: ")"), "paren numbered")
        for text in ["-5 degrees", "3.14 is pi", "plain", "--", "[]", "-"] {
            check(ListLine.parse(text).marker == nil, "not a list line: \(text)")
        }
        var line = ListLine.parse("[ ] a")
        var seen: [String] = []
        for _ in 0..<4 { line = line.cycled(); seen.append(line.formatted) }
        check(seen == ["- a", "1. a", "a", "[ ] a"], "cycle: \(seen)")
        check(ListLine.parse("a").cycled(start: .bullet).formatted == "- a", "cycle from plain uses default style")
        check(ListLine.parse("[ ] a").toggled().formatted == "[x] a", "toggle")
        check(ListLine.parse("- [x] a").toggled().formatted == "- [ ] a", "toggle dashed")
        check(ListLine.parse("2. x").continuation()?.formatted == "3. ", "continue numbering")
        check(ListLine.parse("[x] x").continuation()?.formatted == "[ ] ", "continue unchecked")
        check(ListLine.parse("text").continuation() == nil, "no continuation for plain lines")
        let renumbered = ListLine.renumber(["1. a", "5. b", "\t1. c", "\t7. d", "3. e", "", "9. f", "- g"])
        check(renumbered == ["1. a", "2. b", "\t1. c", "\t2. d", "3. e", "", "1. f", "- g"], "renumber: \(renumbered)")
    }))

    SelfTest.cases.append(("NoteEngine.paste", {
        let messy = "# Title\n\n**bold** and *it* and `code`\n- item\n2. step\n   indented  text  \n[site](https://x.com)\n> quote\n- [ ] task\nsnake_case_name"
        let cleaned = PasteCleaner.clean(messy, options: PasteCleaner.Options())
        let expected = "Title\n\nbold and it and code\nitem\nstep\nindented text\nsite (https://x.com)\nquote\ntask\nsnake_case_name"
        check(cleaned == expected, "clean paste: \(cleaned.debugDescription)")
        var options = PasteCleaner.Options()
        options.removeEmptyLines = true
        check(PasteCleaner.clean("a\n\n\nb\r\n", options: options) == "a\nb", "remove empty lines + CRLF")
        options = PasteCleaner.Options(removeMarkdown: false, removeBullets: false, removeNumbering: false,
                                       removeLeadingWhitespace: false)
        check(PasteCleaner.clean("  - **x**  y", options: options) == "  - **x** y", "only extra spaces removed")
        check(PasteCleaner.clean("# x", options: PasteCleaner.Options(enabled: false)) == "# x", "disabled")
    }))

    SelfTest.cases.append(("NoteEngine.links", {
        let cases = [
            ("https://github.com/owner/repo/pull/42", "github.com/…/pull/42"),
            ("https://www.example.com/", "example.com"),
            ("https://en.wikipedia.org/wiki/A_Psalm_for_the_Wild-Built", "en.wikipedia.org/…/A_Psalm_for_the_Wild-Built"),
            ("https://store.steampowered.com/app/221910/The_Stanley_Parable/", "store.steampowered.com/…/The_Stanley_Parable"),
            ("https://youtube.com/watch?v=abc", "youtube.com/watch?…"),
            ("https://example.com/docs/a%20very%20long%20file%20name%20that%20goes%20on.pdf",
             "example.com/…/a very long file name tha…"),
            ("http://news.ycombinator.com/item", "news.ycombinator.com/item"),
        ]
        for (url, short) in cases {
            let got = makeEngine().shorten(url: url)
            check(got == short, "shorten \(url) → \(got), expected \(short)")
        }
        let found = LinkShortener.detect(in: "see https://a.com/x and www.b.org, or mail me")
        check(found.count == 2 && found.first?.range.location == 4 && found.first?.url.host == "a.com", "detect links")
    }))
}
