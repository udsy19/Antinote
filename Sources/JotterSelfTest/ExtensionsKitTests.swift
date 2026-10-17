import Foundation
import JotterCore
import ExtensionsKit

/// Append cases with `SelfTest.cases.append(("name", { check(..., "msg") }))`.
func registerExtensionsKitTests() {
    SelfTest.cases.append(("ExtensionsKit.invocationParsing", {
        func args(_ s: String) -> [String]? { try? ExtensionInvocation.parse(s).arguments }
        check((try? ExtensionInvocation.parse("::today"))?.name == "today", "bare command")
        check(args("::today") == [] && args("::today()") == [] && args("  ::today( ) ") == [], "empty argument lists")
        check(args(#"::f(a, "b, c", 3)"#) == ["a", "b, c", "3"], "quoted commas")
        check(args("::f((1+2)*3, x)") == ["(1+2)*3", "x"], "nested parentheses")
        check(args("::ask(what's up)") == ["what's up"], "apostrophe inside a word")
        check(args(#"::f("\d+ \"q\"")"#) == [#"\d+ "q""#], "escapes keep unknown backslashes")
        check(args("::f(a,,b)") == ["a", "", "b"], "empty middle argument")
        check((try? ExtensionInvocation.parse(#"::f("open)"#)) == nil, "unclosed quote")
        check((try? ExtensionInvocation.parse("::f(a")) == nil, "unclosed parenthesis")
        check((try? ExtensionInvocation.parse("::f(a) more")) == nil, "text after closing parenthesis")
        check((try? ExtensionInvocation.parse("::")) == nil, "missing name")
    }))

    SelfTest.cases.append(("ExtensionsKit.parameterParsing", {
        let noMath: (String) -> Result<Double, Error> = { _ in .failure(ExtensionError.script("no math")) }
        let spec = CommandSpec(name: "f", aliases: [], type: .insert, helpText: "", parameters: [
            ParameterSpec(name: "days", type: .int, helpText: "", defaultValue: .null, required: true),
            ParameterSpec(name: "rate", type: .float, helpText: "", defaultValue: .number(1.5), required: false),
            ParameterSpec(name: "flag", type: .bool, helpText: "", defaultValue: .bool(false), required: false),
            ParameterSpec(name: "x", type: .expression, helpText: "", defaultValue: .number(0), required: false),
            ParameterSpec(name: "note", type: .paragraph, helpText: "", defaultValue: .string(""), required: false),
        ], tutorials: [])
        func coerce(_ s: String, _ eval: @escaping (String) -> Result<Double, Error> = noMath) throws -> [JSONValue] {
            try ExtensionInvocation.parse(s).coerced(for: spec, evaluate: eval)
        }
        func message(_ s: String) -> String? {
            do { _ = try coerce(s); return nil } catch { return error.localizedDescription }
        }
        check(message("::f") == "Required parameter 'days' is missing", "required parameter message")
        check(message("::f(abc)") == "Parameter 'days' must be a whole number", "int validation")
        check(message("::f(1, x)") == "Parameter 'rate' must be a number", "float validation")
        check(message("::f(1, 2, maybe)") == "Parameter 'flag' must be true or false", "bool validation")
        check((try? coerce("::f(3)")) == [.number(3), .number(1.5), .bool(false), .number(0), .string("")], "defaults fill in")
        check((try? coerce("::f(-2, 0.5, yes, 4)")) == [.number(-2), .number(0.5), .bool(true), .number(4), .string("")], "typed values")
        check((try? coerce("::f(1, , , 2*3)") { _ in .success(6) })?[3] == .number(6), "expressions use the evaluator")
        check((try? coerce("::f(1,2,no,3, What is 2, 3?)"))?[4] == .string("What is 2, 3?"), "surplus text joins the last paragraph")
        let short = CommandSpec(name: "g", aliases: [], type: .insert, helpText: "", parameters: [
            ParameterSpec(name: "n", type: .int, helpText: "", defaultValue: .null, required: true)], tutorials: [])
        check((try? ExtensionInvocation.parse("::g(1, 2)").coerced(for: short, evaluate: noMath)) == nil, "too many arguments")
        check(short.signature == "::g(n)" && spec.signature.contains("rate?"), "signatures mark optional parameters")
    }))

    SelfTest.cases.append(("ExtensionsKit.dataScope", {
        let note = "title\nhello ::cmd(1) there\nend"
        let line = "hello ::cmd(1) there"
        let none = ScopedText(invocation: "::cmd(1)", line: line, note: note, scope: .none)
        let lineScope = ScopedText(invocation: "::cmd(1)", line: line, note: note, scope: .line)
        let full = ScopedText(invocation: "::cmd(1)", line: line, note: note, scope: .full)
        check(none.line == "" && none.fullText == "", "none receives nothing")
        check(lineScope.line == "hello  there" && lineScope.fullText == "hello  there", "line receives only the line")
        check(full.fullText == "title\nhello  there\nend", "full receives the note without the command")
        let alone = ScopedText(invocation: "::sort", line: "::sort", note: "b\n::sort\na", scope: .full)
        check(alone.fullText == "b\na" && alone.line == "", "a line holding only the command is dropped")
    }))

    SelfTest.cases.append(("ExtensionsKit.manifestValidation", {
        func error(_ json: String) -> String? {
            do { _ = try ExtensionManifest.decode(Data(json.utf8)); return nil } catch { return error.localizedDescription }
        }
        check(error(#"{"name":"ok_1","version":"1.0.0"}"#) == nil, "minimal manifest is valid")
        check(error("{nope") == "extension.json is not valid JSON", "invalid JSON")
        check(error(#"{"version":"1.0.0"}"#)?.contains("'name' is required") == true, "missing name")
        check(error(#"{"name":"bad name","version":"1.0.0"}"#)?.contains("may only contain") == true, "invalid name")
        check(error(#"{"name":"x","version":"one"}"#)?.contains("Version 'one'") == true, "invalid version")
        check(error(#"{"name":"x","version":"1.0","dataScope":"all"}"#)?.contains("dataScope 'all'") == true, "invalid data scope")
        check(error(#"{"name":"x","version":"1.0","endpoints":["http://example.com/api"]}"#)?.contains("https") == true, "plain http rejected")
        check(error(#"{"name":"x","version":"1.0","endpoints":["http://localhost:11434/v1"]}"#) == nil, "http allowed for localhost")
        check(error(#"{"name":"x","version":"1.0","files":["../evil.js"]}"#)?.contains("relative .js path") == true, "path traversal rejected")
        check(Version("1.2")! == Version("1.2.0")! && Version("1.10.0")! > Version("1.9.9")!, "version comparison")
    }))

    SelfTest.cases.append(("ExtensionsKit.dependencies", {
        let r = DependencyResolver.resolve(["a": ["b"], "b": ["c"], "c": [], "d": ["missing"], "e": ["f"], "f": ["e"], "g": ["d"]])
        check(r.order == ["c", "b", "a"], "dependencies load first (got \(r.order))")
        check(r.errors["d"] == "'d' depends on 'missing', which is not installed", "missing dependency")
        check(r.errors["e"]?.hasPrefix("Dependency cycle:") == true && r.errors["f"] != nil, "cycle detected")
        check(r.errors["g"] == "'g' depends on 'd', which failed to load", "transitive failure")
        check(DependencyResolver.closure(of: "a", in: ["a": ["b"], "b": ["c"], "c": []], order: ["c", "b", "a"]) == ["c", "b"], "closure in order")
    }))

    SelfTest.cases.append(("ExtensionsKit.networkPolicy", {
        let saved = Defaults[.allowExtensionAPIs]
        defer { Defaults[.allowExtensionAPIs] = saved }
        let policy = NetworkPolicy(endpoints: ["https://api.example.com/v1/chat", "http://localhost:11434/v1"], keyOwners: ["probe"])
        func reason(_ key: String, _ url: String) -> String? {
            if case .failure(let e) = policy.authorize(keyName: key, url: url) { return e.localizedDescription }
            return nil
        }
        Defaults[.allowExtensionAPIs] = false
        check(reason("", "https://api.example.com/v1/chat")?.contains("Privacy") == true, "denied while the privacy switch is off")
        Defaults[.allowExtensionAPIs] = true
        check(reason("", "https://api.example.com/other") == nil, "same host allowed without a key")
        check(reason("", "https://evil.example.org/x")?.contains("not one of this extension's declared endpoints") == true, "undeclared host denied")
        check(reason("", "http://api.example.com/v1/chat") != nil, "scheme must match")
        check(reason("", "http://localhost:8080/v1") != nil, "port must match")
        check(reason("", "http://localhost:11434/v1/chat/completions") == nil, "local endpoint allowed")
        let key = "selftest_unused_key"
        check(reason(key, "https://api.example.com/v1/chat")?.contains("not allowed to use the 'selftest_unused_key'") == true, "ungranted key denied")
        ExtensionStore.setGrant(true, key: key, extension: "probe")
        check(reason(key, "https://api.example.com/v1/chat")?.contains("No 'selftest_unused_key' API key is stored") == true, "missing secret reported")
        ExtensionStore.setGrant(false, key: key, extension: "probe")
        check(ExtensionStore.grants(key).isEmpty, "grant removed")
    }))

    SelfTest.cases.append(("ExtensionsKit.github", {
        let a = try? GitHubSource("https://github.com/owner/repo")
        check(a?.rawURL("extension.json").absoluteString == "https://raw.githubusercontent.com/owner/repo/HEAD/extension.json", "default branch raw URL")
        let b = try? GitHubSource("owner/repo.git")
        check(b?.repo == "repo" && b?.branch == "HEAD", "short form and .git suffix")
        let c = try? GitHubSource("github.com/owner/repo/tree/main/extensions/foo")
        check(c?.rawURL("index.js").absoluteString == "https://raw.githubusercontent.com/owner/repo/main/extensions/foo/index.js", "branch and sub-folder")
        check((try? GitHubSource("https://gitlab.com/owner/repo")) == nil && (try? GitHubSource("repo")) == nil, "non-GitHub URLs rejected")
        MainActor.assumeIsolated {
            let saved = Defaults[.allowExtensionUpdates]
            defer { Defaults[.allowExtensionUpdates] = saved }
            Defaults[.allowExtensionUpdates] = false
            let user = tempDirectory()
            defer { try? FileManager.default.removeItem(at: user) }
            let m = ExtensionsManager(bundledDirectory: nil, userDirectory: user)
            var message: String?
            Task { @MainActor in
                do { try await m.install(fromGitHub: "owner/repo"); message = "installed" } catch { message = error.localizedDescription }
            }
            let deadline = Date().addingTimeInterval(5)
            while message == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            check(message?.contains("turned off") == true, "install refused while GitHub access is off")
        }
    }))

    SelfTest.cases.append(("ExtensionsKit.bundledCommands",{ MainActor.assumeIsolated { bundledCommandTests() } }))
    SelfTest.cases.append(("ExtensionsKit.loading", { MainActor.assumeIsolated { loadingTests() } }))
}

// MARK: - Helpers

/// Saves and restores the Defaults keys extension tests touch.
struct DefaultsSnapshot {
    let values: [String: Any?]
    init(_ names: [String]) { values = Dictionary(uniqueKeysWithValues: names.map { ($0, Defaults.store.object(forKey: $0)) }) }
    func restore() {
        for (name, value) in values {
            if let value { Defaults.store.set(value, forKey: name) } else { Defaults.store.removeObject(forKey: name) }
        }
    }
}

@MainActor
private func run(_ manager: ExtensionsManager, _ invocation: String, line: String? = nil, note: String? = nil) -> ExtensionEdit? {
    var result: ExtensionEdit?
    let line = line ?? invocation
    manager.run(invocation: invocation, line: line, note: note ?? line) { result = $0 }
    let deadline = Date().addingTimeInterval(5)
    while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    return result
}

private func payload(_ edit: ExtensionEdit?) -> String? {
    switch edit {
    case .insert(let s)?, .replaceLine(let s)?, .replaceAll(let s)?, .message(let s)?: return s
    default: return nil
    }
}

private let touchedKeys = ["extensionsEnabled", "allowExtensionAPIs", "extensionLogging", "extensions.disabled",
                           "extensions.prefs.date", "extensions.prefs.lines", "extensions.prefs.llm"]

private func fixedDate() -> Date {
    // Friday 16 October 2026, noon local time.
    Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 12))!
}

private func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("jotter-ext-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeExtension(_ root: URL, folder: String, manifest: String, script: String?) {
    let dir = root.appendingPathComponent(folder)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? manifest.write(to: dir.appendingPathComponent("extension.json"), atomically: true, encoding: .utf8)
    if let script { try? script.write(to: dir.appendingPathComponent("index.js"), atomically: true, encoding: .utf8) }
}

// MARK: - Bundled commands

@MainActor
private func bundledCommandTests() {
    let snapshot = DefaultsSnapshot(touchedKeys)
    defer { snapshot.restore() }
    for name in touchedKeys where name.hasPrefix("extensions.") { Defaults.store.removeObject(forKey: name) }
    Defaults[.extensionsEnabled] = true
    Defaults[.allowExtensionAPIs] = false

    let user = tempDirectory()
    defer { try? FileManager.default.removeItem(at: user) }
    check(ExtensionsManager.bundledExtensionsURL != nil, "bundled extensions folder found")
    let m = ExtensionsManager(userDirectory: user)
    m.clock.fixed = fixedDate()
    check(m.failures.isEmpty, "bundled extensions load: \(m.failures.map(\.message))")
    let names = Set(m.installed.map(\.manifest.name))
    check(names == ["date", "lines", "text", "random", "json", "regex", "finance", "checklists", "templates", "llm"], "all bundled extensions (\(names))")

    // date
    check(run(m, "::today") == .insert("October 16, 2026"), "today, long format")
    check(run(m, "::date(0, iso)") == .insert("2026-10-16"), "alias + format argument")
    check(run(m, "::tomorrow(0, iso)") == .insert("2026-10-17"), "tomorrow")
    check(run(m, "::yesterday(0, us)") == .insert("10/15/2026"), "yesterday")
    check(run(m, "::today(7, eu)") == .insert("23/10/2026"), "offset days")
    check(run(m, "::today(-16, YYYY/MM/DD)") == .insert("2026/09/30"), "custom pattern")
    ExtensionStore.setPreference("date", "format", .string("iso"))
    check(run(m, "::business_day") == .insert("2026-10-19"), "next business day skips the weekend")
    check(run(m, "::business_day(-1)") == .insert("2026-10-15"), "previous business day")
    check(run(m, "::workday(5)") == .insert("2026-10-23"), "five business days")
    check(run(m, "::today(0, weekday)") == .insert("Friday, October 16, 2026"), "weekday format")
    check(run(m, "::today(soon)") == .failure("Parameter 'days' must be a whole number"), "friendly parameter error")
    ExtensionStore.setPreference("date", "format", nil)

    // lines
    func all(_ cmd: String, _ body: String) -> ExtensionEdit? { run(m, cmd, line: cmd, note: body + "\n" + cmd) }
    check(all("::sort", "b\na\nC") == .replaceAll("a\nb\nC"), "sort")
    check(all("::sort", "10\n9\n1") == .replaceAll("1\n9\n10"), "numeric sort")
    check(all("::sort_desc", "b\na\nc") == .replaceAll("c\nb\na"), "sort_desc")
    check(all("::reverse", "1\n2\n3") == .replaceAll("3\n2\n1"), "reverse")
    check(all("::dedupe", "a\nb\na\nb\nc") == .replaceAll("a\nb\nc"), "dedupe")
    check(all("::remove_empty", "a\n\n  \nb") == .replaceAll("a\nb"), "remove_empty")
    check(all("::number_lines", "x\n\ny") == .replaceAll("1. x\n\n2. y"), "number_lines")
    check(all("::trim", "  a \n b") == .replaceAll("a\nb"), "trim")
    let shuffled = payload(all("::shuffle", "1\n2\n3\n4"))?.split(separator: "\n").sorted()
    check(shuffled == ["1", "2", "3", "4"], "shuffle keeps the lines")
    ExtensionStore.setPreference("lines", "keepFirstLine", .bool(true))
    check(all("::sort", "list\nb\na") == .replaceAll("list\na\nb"), "keep first line preference")
    ExtensionStore.setPreference("lines", "keepFirstLine", nil)

    // text
    func line(_ text: String, _ cmd: String) -> ExtensionEdit? { run(m, cmd, line: text + " " + cmd, note: "x\n" + text + " " + cmd) }
    check(line("hello world", "::upper") == .replaceLine("HELLO WORLD"), "upper")
    check(line("Hello World", "::lower") == .replaceLine("hello world"), "lower")
    check(line("the quick brown fox", "::title") == .replaceLine("The Quick Brown Fox"), "title")
    check(line("hELLO there. how ARE you?", "::sentence") == .replaceLine("Hello there. How are you?"), "sentence")
    check(line("Héllo, World! 2026", "::slug") == .replaceLine("hello-world-2026"), "slug")
    check(line("Hello World fooBar", "::snake") == .replaceLine("hello_world_foo_bar"), "snake")
    check(line("hello world foo", "::camel") == .replaceLine("helloWorldFoo"), "camel")
    check(line("a bc", "::count_chars") == .message("4 characters (3 without spaces) · 2 words"), "count_chars")
    check(run(m, "::upper(abc)") == .replaceLine("ABC"), "text argument instead of the line")

    // random
    let dice = payload(run(m, "::dice(2d6)")) ?? ""
    let diceParts = dice.split(separator: "=").last.map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 } ?? 0
    check(dice.hasPrefix("2d6: ") && (2...12).contains(diceParts), "dice NdM (\(dice))")
    check(payload(run(m, "::roll(d20)")).map { $0.hasPrefix("1d20: ") } == true, "dice alias, single die")
    check(run(m, "::dice(0d6)") == .failure("Roll between 1 and 100 dice"), "dice bounds")
    check(run(m, "::dice(abc)") == .failure("Write dice as NdM, for example 2d6"), "dice syntax")
    check(["Heads", "Tails"].contains(payload(run(m, "::coin")) ?? ""), "coin")
    let uuid = payload(run(m, "::uuid")) ?? ""
    check(UUID(uuidString: uuid) != nil && Array(uuid)[14] == "4", "uuid v4 (\(uuid))")
    check(payload(run(m, "::password(16)"))?.count == 16, "password length")
    let plain = payload(run(m, "::password(30, false)")) ?? "!"
    check(plain.count == 30 && plain.allSatisfy { $0.isLetter || $0.isNumber }, "password without symbols")
    check(["pizza", "sushi", "tacos"].contains(payload(run(m, "::pick(pizza, sushi, tacos)")) ?? ""), "pick")
    check(run(m, "::pick") == .failure("Required parameter 'items' is missing"), "pick needs items")

    // json
    let json = #"{"b":1,"a":[1,2]}"#
    check(all("::format", json) == .replaceAll("{\n  \"b\": 1,\n  \"a\": [\n    1,\n    2\n  ]\n}"), "json format")
    check(all("::minify", "{\n  \"b\" : 1,\n \"a\": [1, 2]\n}") == .replaceAll(json), "json minify")
    check(all("::validate", json) == .message("Valid JSON (object with 2 keys)"), "json validate")
    if case .failure(let message)? = all("::validate", "{oops") { check(message.hasPrefix("Invalid JSON"), "invalid JSON message") }
    else { check(false, "invalid JSON fails") }

    // regex
    check(all(#"::replace_regex(\d+, #)"#, "a1 b22") == .replaceAll("a# b#"), "regex replace")
    check(all(#"::replace_regex("(\w+)@(\w+)", "$2 at $1")"#, "me@home") == .replaceAll("home at me"), "regex groups")
    check(all("::regex(TODO, done, gi)", "todo Todo") == .replaceAll("done done"), "regex flags + alias")
    if case .failure(let message)? = all("::replace_regex(\"(\")", "x") { check(message.hasPrefix("Invalid regular expression"), "bad pattern") }
    else { check(false, "bad pattern fails") }

    // finance
    check(run(m, "::loan(300000, 6.5, 30)") == .insert("Monthly payment: 1,896.20 · Total paid: 682,633.47 · Interest: 382,633.47"), "loan")
    check(run(m, "::tip(100)") == .insert("Tip: 18.00 · Total: 118.00"), "tip default")
    check(run(m, "::tip(120, 20, 4)") == .insert("Tip: 24.00 · Total: 144.00 · Each: 36.00"), "tip split")
    check(run(m, "::percent_change(80, 100)") == .insert("+25.00%"), "percent increase")
    check(run(m, "::percent_change(100, 80)") == .insert("-20.00%"), "percent decrease")
    check(run(m, "::compound(10000, 5, 10, 1)") == .insert("Future value: 16,288.95 · Interest earned: 6,288.95"), "compound")
    check(run(m, "::loan(1000)") == .failure("Required parameter 'rate' is missing"), "loan needs a rate")

    // checklists
    let list = "[ ] a\n[x] b\n- [X] c"
    check(all("::remove_checked", list) == .replaceAll("[ ] a"), "remove_checked")
    check(all("::check_all", list) == .replaceAll("[x] a\n[x] b\n- [x] c"), "check_all")
    check(all("::uncheck_all", list) == .replaceAll("[ ] a\n[ ] b\n- [ ] c"), "uncheck_all")
    check(all("::checked_to_bottom", "[x] a\n[ ] b") == .replaceAll("[ ] b\n[x] a"), "checked_to_bottom")
    check(all("::check_all", "plain") == .failure("This note has no [ ] checklist items"), "no checklist")

    // templates (depends on date)
    check(payload(run(m, "::meeting(Design review)"))?.hasPrefix("Meeting: Design review — October 16, 2026\n") == true, "meeting")
    check(payload(run(m, "::standup"))?.hasPrefix("Standup — October 16, 2026\n\nYesterday:") == true, "standup")
    check(payload(run(m, "::journal"))?.hasPrefix("Journal — Friday, October 16, 2026") == true, "journal")

    // llm: no network without the privacy switch, and keys must be granted
    if case .failure(let message)? = run(m, "::ask(Hello there)") { check(message.contains("Privacy"), "llm blocked by privacy switch: \(message)") }
    else { check(false, "llm fails without the APIs switch") }
    Defaults[.allowExtensionAPIs] = true
    ExtensionStore.setPreference("llm", "provider", .string("openai"))
    if ExtensionStore.grants("openai").contains("llm") == false {
        if case .failure(let message)? = run(m, "::ask(Hello there)") { check(message.contains("not allowed to use the 'openai' API key"), "llm needs a granted key: \(message)") }
        else { check(false, "llm fails without a granted key") }
    }
    if case .failure(let message)? = run(m, "::translate(French)", line: "::translate(French)", note: "::translate(French)") {
        check(message.contains("Write the text to translate"), "translate needs text")
    } else { check(false, "translate fails without text") }

    // autocomplete, aliases, enablement
    check(m.complete("tod").first?.name == "today", "complete by prefix")
    check(m.complete("::sor").first?.name == "sort", "complete strips ::")
    check(m.complete("date").first?.name == "today", "complete matches aliases")
    check(m.complete("").count == m.commands.count && m.commands.count > 40, "empty prefix lists everything")
    m.setEnabled(false, "date")
    check(run(m, "::today") == .failure("Unknown command ::today"), "disabled extension's commands are unavailable")
    check(!m.commands.contains { $0.extensionName == "date" }, "disabled extension hidden from commands")
    m.setEnabled(true, "date")
    Defaults[.extensionsEnabled] = false
    check(m.commands.isEmpty, "master switch hides commands")
    check(run(m, "::today") == .failure("Extensions are turned off. Turn them on in Settings → Extensions."), "master switch blocks runs")
    Defaults[.extensionsEnabled] = true
    check(run(m, "::nope") == .failure("Unknown command ::nope"), "unknown command")
    _ = m.makeSettingsView()
}

// MARK: - Loading, scope enforcement, manifests

@MainActor
private func loadingTests() {
    let snapshot = DefaultsSnapshot(touchedKeys)
    defer { snapshot.restore() }
    Defaults[.extensionsEnabled] = true
    let user = tempDirectory()
    defer { try? FileManager.default.removeItem(at: user) }

    for scope in ["none", "line", "full"] {
        writeExtension(user, folder: "probe_\(scope)", manifest: #"{"name":"probe_\#(scope)","version":"1.0.0","dataScope":"\#(scope)"}"#, script: """
        (function () {
          var ext = new Extension({ name: "probe_\(scope)", dataScope: "full" });
          new Command({ name: "echo_\(scope)", type: "insert", parameters: [], extension: ext,
            execute: function (p) { return new ReturnObject({ status: "success", payload: "[" + p.line + "|" + p.fullText + "]" }); } });
        })();
        """)
    }
    // Positional (older) constructor form, as in published samples.
    writeExtension(user, folder: "positional", manifest: #"{"name":"positional","version":"0.1"}"#, script: """
    var e = new Extension("positional", "0.1", [], [], "me", "Misc", "none");
    var c = new Command("shout", [new Parameter("string", "word", "help", "hey", false)], "insert", "Shout", [], e);
    c.execute = function (payload) { var p = this.getParsedParams(payload); console.log("shouting"); return p[0].toUpperCase() + "!"; };
    """)
    writeExtension(user, folder: "needs_base", manifest: #"{"name":"needs_base","version":"1.0.0","dependencies":["base_service"]}"#, script: """
    (function () {
      var ext = new Extension({ name: "needs_base" });
      new Command({ name: "use_base", type: "insert", parameters: [], extension: ext, execute: function () { return greet(); } });
    })();
    """)
    writeExtension(user, folder: "base_service", manifest: #"{"name":"base_service","version":"1.0.0","isService":true}"#, script: """
    new Extension({ name: "base_service", isService: true });
    global.greet = function () { return "from service"; };
    """)
    writeExtension(user, folder: "orphan", manifest: #"{"name":"orphan","version":"1.0.0","dependencies":["ghost"]}"#, script: "new Extension({name: 'orphan'});")
    writeExtension(user, folder: "no_script", manifest: #"{"name":"no_script","version":"1.0.0"}"#, script: nil)
    writeExtension(user, folder: "mismatch", manifest: #"{"name":"mismatch","version":"1.0.0"}"#, script: "new Extension({name: 'other'});")
    writeExtension(user, folder: "throws", manifest: #"{"name":"throws","version":"1.0.0"}"#, script: "throw new Error('boom');")
    writeExtension(user, folder: "bad_manifest", manifest: #"{"name":"bad manifest","version":"1.0.0"}"#, script: "")

    let m = ExtensionsManager(bundledDirectory: nil, userDirectory: user)
    let loaded = Set(m.installed.map(\.manifest.name))
    check(loaded == ["probe_none", "probe_line", "probe_full", "positional", "needs_base", "base_service"], "loaded set (\(loaded))")
    func failure(_ folder: String) -> String? { m.failures.first { $0.folder.lastPathComponent == folder }?.message }
    check(failure("orphan") == "'orphan' depends on 'ghost', which is not installed", "missing dependency reported")
    check(failure("no_script") == "Missing script file 'index.js'", "missing index.js reported")
    check(failure("mismatch") == "index.js registers 'other' but extension.json says 'mismatch'", "name mismatch reported")
    check(failure("throws")?.contains("boom") == true, "script exception reported")
    check(failure("bad_manifest")?.contains("may only contain") == true, "invalid manifest reported")

    let note = "first\nsecret ::echo_X here\nlast"
    func echo(_ scope: String) -> ExtensionEdit? {
        let inv = "::echo_\(scope)"
        return run(m, inv, line: "secret \(inv) here", note: note.replacingOccurrences(of: "::echo_X", with: inv))
    }
    check(echo("none") == .insert("[|]"), "dataScope none hides the note")
    check(echo("line") == .insert("[secret  here|secret  here]"), "dataScope line gives only the line")
    check(echo("full") == .insert("[secret  here|first\nsecret  here\nlast]"), "dataScope full gives the note")

    check(run(m, "::shout") == .insert("HEY!"), "positional constructors and string results")
    check(run(m, "::shout(hi)") == .insert("HI!"), "positional parameter")
    check(run(m, "::use_base") == .insert("from service"), "dependency globals available")
    check(!m.commands.contains { $0.extensionName == "base_service" }, "service registers no commands")
    check(m.commands.filter { $0.name == "use_base" }.count == 1, "dependency commands not duplicated")
}
