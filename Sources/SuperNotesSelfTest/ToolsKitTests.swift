import Foundation
import SuperNotesCore
import ToolsKit

/// Append cases with `SelfTest.cases.append(("name", { check(..., "msg") }))`.
func registerToolsKitTests() {
    SelfTest.cases.append(("ToolsKit.timerSpecParsing", {
        func spec(_ s: String) -> TimerSpec? {
            if case let .success(.start(spec)) = TimerSpec.parse(s) { return spec }
            return nil
        }
        func error(_ s: String) -> TimerParseError? {
            if case let .failure(e) = TimerSpec.parse(s) { return e }
            return nil
        }
        check(spec("")?.kind == .stopwatch, "empty → stopwatch")
        check(spec("stopwatch")?.kind == .stopwatch, "stopwatch keyword")
        check(spec("5")?.kind == .countdown(300), "bare number = minutes")
        check(spec("25m")?.kind == .countdown(1500), "25m")
        check(spec("90s")?.kind == .countdown(90), "90s")
        check(spec("10:00")?.kind == .countdown(600), "m:ss")
        check(spec("1:30:00")?.kind == .countdown(5400), "h:mm:ss")
        check(spec("1h30m")?.kind == .countdown(5400), "1h30m")
        check(spec("1h 30m")?.kind == .countdown(5400), "1h 30m adds up")
        check(spec("countdown 5m")?.kind == .countdown(300), "countdown keyword")
        check(spec("timer 5m tea") == TimerSpec(kind: .countdown(300), name: "tea"), "trailing name")
        check(spec("1.5h")?.kind == .countdown(5400) && spec("timer 1:02:03")?.kind == .countdown(3723), "fractional and h:mm:ss")
        check(spec("timer 57 11")?.kind == .pomodoro(work: 3420, rest: 660), "custom pomodoro")
        check(spec("5:30 : Laundry") == TimerSpec(kind: .countdown(330), name: "Laundry"), "colon name keeps case")
        check(spec("pomodoro")?.kind == .pomodoro(work: 1500, rest: 300), "pomodoro defaults")
        check(spec("pomo")?.kind == .pomodoro(work: 1500, rest: 300), "pomo")
        check(spec("pomodoro 52 17")?.kind == .pomodoro(work: 3120, rest: 1020), "custom pomodoro")
        check(spec("52 17")?.kind == .pomodoro(work: 3120, rest: 1020), "two numbers → pomodoro")
        check(spec("pomo 50m 10m")?.kind == .pomodoro(work: 3000, rest: 600), "same units stay separate")
        check(spec("breathe")?.kind == .breathe, "breathe")
        check(TimerSpec.parse("p") == .success(.control(.togglePause)), "p pauses")
        check(TimerSpec.parse("r") == .success(.control(.reset)), "r resets")
        check(TimerSpec.parse("s") == .success(.control(.stop)), "s stops")
        check(error("0") == .zeroCountdown, "zero countdown")
        check(error("0:00") == .zeroCountdown, "zero clock")
        check(error("pomodoro 0 5") == .zeroPomodoro, "zero pomodoro")
        check(error("1 2 3") == .tooManyNumbers, "three numbers")
        check(error("stopwatch 5") == .unparseable, "stopwatch with a duration")
        check(TimerParseError.zeroCountdown.message == "Cannot countdown zero minutes", "message text")
        check(TimerFormat.clock(65) == "01:05" && TimerFormat.clock(3723) == "1:02:03", "clock format")
        check(TimerFormat.spoken(5400) == "1 h 30 min" && TimerFormat.spoken(45) == "45 s", "spoken format")
    }))

    SelfTest.cases.append(("ToolsKit.timerStateMachine", {
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
        func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

        var countdown = TimerRun(spec: TimerSpec(kind: .countdown(60), name: "tea"), now: t0)
        check(countdown.statusText(at: t0) == "01:00 · tea", "starts at full time")
        check(countdown.statusText(at: at(0.4)) == "01:00 · tea", "rounds remaining up")
        countdown.pause(at: at(20))
        check(countdown.statusText(at: at(50)) == "00:40 · tea · paused", "paused freezes time")
        countdown.resume(at: at(50))
        check(countdown.snapshot(at: at(60)).seconds == 30, "resume continues")
        check(countdown.events(from: at(70), to: at(91)) == [.finished], "finish event")
        check(countdown.events(from: at(91), to: at(95)).isEmpty, "finish fires once")
        check(countdown.isFinished(at: at(90)) && countdown.statusText(at: at(95)) == "Done · tea", "done")
        countdown.reset(at: at(100))
        check(!countdown.isFinished(at: at(100)) && countdown.snapshot(at: at(110)).seconds == 50, "reset restarts")

        let pomo = TimerRun(spec: TimerSpec(kind: .pomodoro(work: 25 * 60, rest: 5 * 60)), now: t0)
        check(pomo.snapshot(at: at(10)).phase == .work(1), "work first")
        check(pomo.snapshot(at: at(25 * 60)).phase == .rest(1), "break after work")
        check(pomo.statusText(at: at(26 * 60)) == "04:00 · break 1", "break status")
        check(pomo.snapshot(at: at(30 * 60 + 1)).phase == .work(2), "second session")
        check(pomo.events(from: at(24 * 60), to: at(25 * 60 + 1)) == [.workEnded(1)], "work ended")
        check(pomo.events(from: at(29 * 60), to: at(30 * 60 + 1)) == [.breakEnded(1)], "break ended")
        check(pomo.events(from: at(0), to: at(61 * 60)) == [.workEnded(1), .breakEnded(1), .workEnded(2), .breakEnded(2)],
              "every crossing reported after a long gap")

        let watch = TimerRun(spec: TimerSpec(kind: .stopwatch), now: t0)
        check(watch.statusText(at: at(3725)) == "1:02:05", "stopwatch counts up")
        check(watch.events(from: t0, to: at(10_000)).isEmpty, "stopwatch has no events")

        let breathe = TimerRun(spec: TimerSpec(kind: .breathe), now: t0)
        check(breathe.snapshot(at: at(1)).phase == .breatheIn && breathe.snapshot(at: at(5)).phase == .breatheOut,
              "breathing rhythm")

        let data = try? JSONEncoder().encode(pomo)
        check(data.flatMap { try? JSONDecoder().decode(TimerRun.self, from: $0) } == pomo, "runs persist as JSON")
    }))

    SelfTest.cases.append(("ToolsKit.urlCommands", {
        func parse(_ s: String) -> URLCommand? { URL(string: s).flatMap(URLCommand.parse) }
        let id = UUID()
        check(parse("supernotes://new?text=Hello%20world") == .new("Hello world"), "new")
        check(parse("supernotes://append?text=milk%0Aeggs") == .append("milk\neggs"), "append decodes newlines")
        check(parse("supernotes://overwrite?text=x") == .overwrite("x"), "overwrite")
        check(parse("supernotes://show?id=\(id.uuidString)") == .show(id), "show")
        check(parse("supernotes://promote?id=\(id.uuidString)") == .promote(id), "promote")
        check(parse("supernotes://promote?id=nope") == nil, "invalid id")
        check(parse("supernotes://TogglePin") == .togglePin, "case-insensitive")
        check(parse("supernotes://search?q=tea%20cups") == .search("tea cups"), "search")
        check(parse("supernotes://palette") == .palette && parse("supernotes://void") == .void, "panels")
        check(parse("supernotes:new?text=a") == .new("a"), "no slashes")
        check(parse("other://new?text=a") == nil && parse("supernotes://explode") == nil, "rejects others")
        check(URLCommand.appending("b", to: "a") == "a\nb" && URLCommand.appending("b", to: "a\n") == "a\nb"
              && URLCommand.appending("b", to: "") == "b", "appending")
    }))

    SelfTest.cases.append(("ToolsKit.exportText", {
        check(ExportText.body("list\nmilk", omitKeyword: true) == "milk", "omit keyword line")
        check(ExportText.body("list\nmilk", omitKeyword: false) == "list\nmilk", "keep keyword")
        check(ExportText.body("Groceries\nmilk", omitKeyword: true) == "Groceries\nmilk", "plain notes untouched")
        check(ExportText.markdown("☐ milk\n  ☑ eggs\n• bread\nplain") == "- [ ] milk\n  - [x] eggs\n- bread\nplain",
              "marker conversion keeps indentation")
        check(ExportText.markdown("[ ] a\n[x] b") == "- [ ] a\n- [x] b", "bracket markers")
        check(ExportText.markdownDocument("todo\nmilk\n☑ eggs\n\nbread", omitKeyword: true)
              == "- [ ] milk\n- [x] eggs\n\n- [ ] bread", "checklist items become tasks")
        check(ExportText.markdownDocument("todo\nmilk", omitKeyword: false) == "todo\n- [ ] milk", "kept keyword line")
        check(ExportText.title(of: "\n  Hello \nworld") == "Hello" && ExportText.title(of: "") == "Untitled", "title")
        check(ExportText.fileName("a/b: c", ext: "md") == "a-b- c.md", "safe file names")
        check(ExportText.queryValue("a b&c=é") == "a%20b%26c%3D%C3%A9", "query encoding")
        check(ExportText.html("<b>\n") == "<div>&lt;b&gt;</div><div><br></div>", "html escaping")
    }))

    SelfTest.cases.append(("ToolsKit.fuzzyMatcher", {
        let titles = ["Settings: Appearance", "New Note", "Export to Markdown (.md)", "The Void", "Start Stopwatch"]
        let ranked = FuzzyMatcher.rank(titles, query: "nn") { $0 }.map(\.item)
        check(ranked.first == "New Note", "word starts win")
        check(FuzzyMatcher.rank(titles, query: "void") { $0 }.first?.item == "The Void", "substring")
        check(FuzzyMatcher.match("xyz", in: "New Note") == nil, "non-match")
        check(FuzzyMatcher.match("new", in: "New Note")!.score > FuzzyMatcher.match("new", in: "Renew Note")!.score,
              "prefix beats middle")
        check(FuzzyMatcher.match("New Note", in: "new note")!.score > FuzzyMatcher.match("new", in: "new note")!.score,
              "exact match is best")
        check(FuzzyMatcher.match("sw", in: "Start Stopwatch")?.indices == [0, 10], "indices reported")
        check(FuzzyMatcher.match("", in: "anything")?.score == 0, "empty query matches all")
        let tie = FuzzyMatcher.rank(["b x", "a x"], query: "x") { $0 }.map(\.item)
        check(tie == ["b x", "a x"], "ties keep order")

        let snippet = SearchSnippet.make("Shopping\nbuy Milk and more milk\nend", query: "milk")
        check(snippet.text == "buy Milk and more milk" && snippet.highlights.count == 2, "snippet line with all hits")
        let long = SearchSnippet.make(String(repeating: "a", count: 100) + " key " + String(repeating: "b", count: 100),
                                      query: "key", radius: 10)
        check(long.text.hasPrefix("…") && long.text.hasSuffix("…") && long.highlights.count == 1, "long lines trimmed")
    }))

    SelfTest.cases.append(("ToolsKit.searchModel", {
        let a = Note(content: "list\n[ ] Milk\n[x] eggs\n\nbread"), b = Note(content: "Slotted milk", slot: 2)
        let c = Note(content: "math: Budget\nrent: 1200"), archived = Note(content: "old milk", isArchived: true)
        let deck = [a, b, c]
        check(SearchModel.results(query: "", scope: .ephemeral, deck: deck, archived: [archived]).map(\.id) == [a.id, c.id],
              "empty query lists the ephemeral deck in order")
        check(SearchModel.results(query: "MILK", scope: .ephemeral, deck: deck, archived: []).map(\.id) == [a.id],
              "case-insensitive match within scope")
        check(SearchModel.results(query: "milk", scope: .slotted, deck: deck, archived: []).map(\.id) == [b.id], "slotted scope")
        check(SearchModel.results(query: " Archived ", scope: .ephemeral, deck: deck, archived: [archived]).map(\.id)
              == [archived.id], "“archived” browses archived notes")
        check(SearchModel.listPreview(a.content) == "Milk  |  eggs  |  bread", "keyword dropped, markers removed, joined")
        check(SearchModel.listPreview(c.content) == "Budget  |  rent: 1200", "keyword title kept")
        check(SearchModel.previewLines("- [ ] tea\n\tindented") == ["tea", "\tindented"], "dash checkbox stripped")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US")
        let now = Date(timeIntervalSince1970: 1_760_000_000)   // 2025-10-09
        check(SearchModel.meta(modified: now.addingTimeInterval(-6 * 3600), now: now, calendar: calendar, locale: locale)
              == "Edited 6 hours ago", "recent notes say how long ago")
        check(SearchModel.meta(modified: now.addingTimeInterval(-20), now: now, calendar: calendar, locale: locale)
              == "Edited just now", "just now")
        check(SearchModel.meta(modified: now.addingTimeInterval(-60 * 86_400), now: now, calendar: calendar, locale: locale)
              == "August 10", "older notes show the date")
        check(SearchModel.meta(modified: now.addingTimeInterval(-400 * 86_400), now: now, calendar: calendar, locale: locale)
              == "September 4, 2024", "other years include the year")
    }))

    SelfTest.cases.append(("ToolsKit.noPeekStreak", {
        var streak = NoPeekStreak()
        streak.breakCompleted(); streak.breakCompleted()
        check(streak == NoPeekStreak(current: 2, best: 2), "breaks sat out count up")
        streak.peeked()
        check(streak == NoPeekStreak(current: 0, best: 2), "a peek resets the streak, best stays")
        streak.breakCompleted()
        check(streak == NoPeekStreak(current: 1, best: 2), "best only grows when beaten")
    }))
}
