import AppKit
import Combine
import CryptoKit
import SuperNotesCore
import ExtensionsKit
import AIKit

/// The AI engines: engine choice, the background download (over a fake server), the JavaScript bridge over a
/// fake engine, the command-line engine over fake executables, and, when a GGUF is at hand, the real model.
func registerAIKitTests() {
    SelfTest.cases.append(("AIKit.engineSelection", {
        typealias A = EngineSelection.Availability
        func pick(_ preferred: AIEngineKind?, apple: Bool, tool: Bool = false) -> AIEngineKind {
            EngineSelection.resolve(preferred: preferred, available: A(appleModel: apple, commandLineTool: tool))
        }
        check(pick(nil, apple: false) == .onDevice && pick(nil, apple: true) == .apple, "nothing picked: Apple's model where present, else the download")
        check(pick(.onDevice, apple: true) == .onDevice, "the downloaded model when picked")
        check(pick(.apple, apple: false) == .onDevice && pick(.apple, apple: true) == .apple, "Apple's model only where the Mac has it")
        check(pick(.commandLine, apple: true) == .commandLine && pick(.commandLine, apple: false, tool: false) == .commandLine,
              "a picked command-line tool is used even before one is found (readiness explains)")
        check(EngineSelection.shouldDownload(engine: .onDevice, autoDownload: true, installed: false), "download for the on-device engine")
        check(!EngineSelection.shouldDownload(engine: .onDevice, autoDownload: false, installed: false), "not when turned off")
        check(!EngineSelection.shouldDownload(engine: .onDevice, autoDownload: true, installed: true), "not when installed")
        check(!EngineSelection.shouldDownload(engine: .apple, autoDownload: true, installed: false), "not for a Mac on Apple's model")

        let fine = DownloadConditions(networkOK: true, lowPowerMode: false, freeDiskBytes: 50_000_000_000)
        check(fine.blocker == nil, "good conditions")
        check(DownloadConditions(networkOK: false, lowPowerMode: false, freeDiskBytes: 50_000_000_000).blocker == .network, "metered or no network")
        check(DownloadConditions(networkOK: true, lowPowerMode: true, freeDiskBytes: 50_000_000_000).blocker == .lowPower, "Low Power Mode")
        check(DownloadConditions(networkOK: false, lowPowerMode: true, freeDiskBytes: 9_999_999_999).blocker == .disk, "disk comes first")
        check(ModelDownloader.retryDelay(afterFailures: 1) == 60 && ModelDownloader.retryDelay(afterFailures: 4) == 480
              && ModelDownloader.retryDelay(afterFailures: 20) == 3600, "retry gap doubles up to an hour")
        check(ModelCatalog.default.url.host == "huggingface.co" && ModelCatalog.default.sha256.count == 64
              && ModelCatalog.default.bytes == 1_280_835_840 && ModelCatalog.default.licence == "Apache-2.0", "catalog entry")
        check(ModelSpec.sizeText(1_280_835_840) == "1.28 GB" && ModelSpec.sizeText(532_517_120) == "532.5 MB", "sizes")
    }))

    SelfTest.cases.append(("AIKit.textPieces", {
        var pieces = UTF8Pieces()
        let euro = Array("€".utf8)   // E2 82 AC
        check(pieces.feed(Array("a".utf8) + [euro[0]]) == "a", "a lead byte waits")
        check(pieces.feed([euro[1]]) == "" && pieces.feed([euro[2]] + Array("b".utf8)) == "€b", "joined across pieces")
        check(pieces.flush() == "", "nothing pending")
        var filter = ThinkFilter()
        check(filter.feed("<thi") == "" && filter.feed("nk>\nhmm") == "" && filter.feed("\n</think>\n\nFour") == "Four"
              && filter.feed(" more") == " more", "a leading think block is held back")
        var plain = ThinkFilter()
        check(plain.feed("The") == "The" && plain.feed(" answer") == " answer", "plain text passes at once")
        var maybe = ThinkFilter()
        check(maybe.feed("<t") == "" && maybe.feed("able>") == "<table>", "a tag that isn't <think> is released")
        var unclosed = ThinkFilter()
        check(unclosed.feed("<think>lost") == "" && unclosed.flush(" words") == "lost words", "an unclosed block gives up its text")
    }))

    SelfTest.cases.append(("AIKit.downloadManager", { MainActor.assumeIsolated { downloadManagerTests() } }))
    SelfTest.cases.append(("AIKit.jsBridge", { MainActor.assumeIsolated { jsBridgeTests() } }))
    SelfTest.cases.append(("AIKit.commandLineEngine", { MainActor.assumeIsolated { commandLineTests() } }))
    SelfTest.cases.append(("AIKit.llamaSmoke", { MainActor.assumeIsolated { llamaSmokeTest() } }))
}

// MARK: - Helpers

@MainActor
private func pump(until condition: @MainActor () -> Bool, seconds: TimeInterval = 5) {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
}

private func scratch(_ name: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("supernotes-ai-tests-\(name)-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func hex(_ digest: SHA256Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

// MARK: - Download manager over a fake server

/// Serves one payload with `Range` support and can drop the connection part-way, once.
private final class FakeModelServer: URLProtocol {
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var cutAfter: Int?
    nonisolated(unsafe) static var honorsRange = true
    nonisolated(unsafe) static var ranges: [String?] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (payload, cut, honors): (Data, Int?, Bool) = Self.lock.withLock {
            Self.ranges.append(request.value(forHTTPHeaderField: "Range"))
            defer { Self.cutAfter = nil }
            return (Self.payload, Self.cutAfter, Self.honorsRange)
        }
        let start = request.value(forHTTPHeaderField: "Range").flatMap { Int($0.dropFirst("bytes=".count).dropLast()) } ?? 0
        let body: Data
        let response: HTTPURLResponse
        if start > 0 && honors {
            body = payload[start...]
            response = HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: [
                "Content-Range": "bytes \(start)-\(payload.count - 1)/\(payload.count)", "Content-Length": "\(body.count)"])!
        } else {
            body = payload
            response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Length": "\(body.count)"])!
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let limit = cut.map { min($0, body.count) } ?? body.count
        var offset = 0
        while offset < limit {
            let end = min(limit, offset + 4096)
            client?.urlProtocol(self, didLoad: body[body.startIndex + offset ..< body.startIndex + end])
            offset = end
        }
        if cut != nil {
            // The drop comes a moment after the bytes, the way a real connection goes, so the bytes are delivered.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [self] in
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            }
        } else { client?.urlProtocolDidFinishLoading(self) }
    }

    override func stopLoading() {}
}

@MainActor
private func downloadManagerTests() {
    let folder = scratch("download")
    defer { try? FileManager.default.removeItem(at: folder) }
    var payload = Data(count: 50_000)
    for i in 0..<payload.count { payload[i] = UInt8(truncatingIfNeeded: i &* 31 &+ 7) }
    FakeModelServer.payload = payload
    FakeModelServer.honorsRange = true
    FakeModelServer.ranges = []
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FakeModelServer.self]
    let spec = ModelSpec(id: "test", displayName: "Test model", fileName: "test.gguf", url: URL(string: "https://example.invalid/test.gguf")!,
                         sha256: hex(SHA256.hash(data: payload)), bytes: Int64(payload.count), licence: "MIT")
    var conditions = DownloadConditions(networkOK: true, lowPowerMode: false, freeDiskBytes: 50_000_000_000)
    nonisolated(unsafe) var current = conditions
    let d = ModelDownloader(spec: spec, folder: folder, configuration: config, conditions: { current })
    check(d.state == .notInstalled && !d.isInstalled, "nothing installed yet")

    // Guards: a short disk waits a day, Low Power Mode and a metered network wait for the system's call.
    conditions.freeDiskBytes = 5_000_000_000; current = conditions
    d.start()
    check(d.state == .waiting(.disk), "short disk: \(d.state)")
    check(d.nextAttempt.map { abs($0.timeIntervalSinceNow - ModelDownloader.diskRetryInterval) < 5 } == true, "disk is looked at again daily")
    conditions.freeDiskBytes = 50_000_000_000; conditions.lowPowerMode = true; current = conditions
    d.conditionsChanged()
    check(d.state == .waiting(.lowPower), "Low Power Mode: \(d.state)")
    conditions.lowPowerMode = false; conditions.networkOK = false; current = conditions
    d.conditionsChanged()
    check(d.state == .waiting(.network), "metered network: \(d.state)")
    check(FakeModelServer.ranges.isEmpty, "no request was made while blocked")

    // A pause mid-download keeps the partial file.
    conditions.networkOK = true; current = conditions
    d.conditionsChanged()
    check(d.isActive, "download started")
    conditions.lowPowerMode = true; current = conditions
    d.conditionsChanged()
    check(d.state == .waiting(.lowPower) && !d.isActive, "paused: \(d.state)")
    pump(until: { false }, seconds: 0.3)
    check(d.state == .waiting(.lowPower), "the cancelled task doesn't change the state")

    // The connection drops after 10 000 bytes: a failure with a retry gap, and the partial file keeps the bytes.
    conditions.lowPowerMode = false; current = conditions
    FakeModelServer.cutAfter = 10_000
    FakeModelServer.ranges = []
    d.conditionsChanged()
    pump(until: { if case .failed = d.state { return true }; return false })
    guard case .failed = d.state else { return check(false, "dropped connection fails: \(d.state)") }
    check(d.failures == 1 && d.nextAttempt.map { abs($0.timeIntervalSinceNow - 60) < 5 } == true, "first retry in a minute")
    let partialSize = (try? FileManager.default.attributesOfItem(atPath: d.partialURL.path)[.size] as? Int) ?? -1
    check(partialSize == 10_000, "partial file holds what arrived (\(partialSize))")

    // The retry resumes with a Range request from the partial file's end and the hash matches.
    d.retryNow()
    pump(until: { d.state == .installed })
    check(d.state == .installed && d.isInstalled, "resumed download installed: \(d.state)")
    check(FakeModelServer.ranges.last == "bytes=10000-", "resumed from byte 10 000 (\(FakeModelServer.ranges))")
    check(!FileManager.default.fileExists(atPath: d.partialURL.path), "partial file gone")
    check((try? Data(contentsOf: d.fileURL)) == payload, "the installed bytes are the server's")
    check(d.failures == 0 && d.nextAttempt == nil, "a success clears the retry")

    // A server that ignores the range starts the file over and still lands it.
    d.remove()
    check(d.state == .notInstalled && !FileManager.default.fileExists(atPath: d.fileURL.path), "removed")
    FakeModelServer.honorsRange = false
    FakeModelServer.cutAfter = 20_000
    d.start()
    pump(until: { if case .failed = d.state { return true }; return false })
    d.retryNow()
    pump(until: { d.state == .installed })
    check(d.state == .installed && (try? Data(contentsOf: d.fileURL)) == payload, "a 200 answer to a Range request restarts cleanly")
    FakeModelServer.honorsRange = true

    // A wrong hash is never installed; the partial file is thrown away.
    let wrong = ModelSpec(id: "wrong", displayName: "Wrong", fileName: "wrong.gguf", url: spec.url,
                          sha256: String(repeating: "0", count: 64), bytes: spec.bytes, licence: "MIT")
    let w = ModelDownloader(spec: wrong, folder: folder, configuration: config, conditions: { current })
    w.start()
    pump(until: { if case .failed = w.state { return true }; return false })
    check(w.state == .failed("The download didn't match its SHA-256") && !w.isInstalled, "checksum mismatch: \(w.state)")
    check(!FileManager.default.fileExists(atPath: w.partialURL.path) && !FileManager.default.fileExists(atPath: w.fileURL.path),
          "nothing kept after a mismatch")

    // A server with a file of another size is refused before any bytes are kept.
    let other = ModelSpec(id: "other", displayName: "Other", fileName: "other.gguf", url: spec.url, sha256: spec.sha256,
                          bytes: spec.bytes + 1, licence: "MIT")
    let o = ModelDownloader(spec: other, folder: folder, configuration: config, conditions: { current })
    o.start()
    pump(until: { if case .failed = o.state { return true }; return false })
    if case .failed(let message) = o.state { check(message.contains("different size"), "size mismatch: \(message)") }
    else { check(false, "size mismatch fails: \(o.state)") }
    o.stop()

    // "Getting ready… 40%" from the state.
    check(ModelDownloader.State.downloading(received: 40, total: 100).preparingText == "Getting ready… 40%", "progress pill")
    check(ModelDownloader.State.installed.preparingText == nil, "no pill when installed")
}

// MARK: - The JavaScript bridge over a fake engine

@MainActor
private final class FakeAI: AIServicing {
    var readiness: AIReadiness = .ready { didSet { subject.send(readiness) } }
    private let subject = PassthroughSubject<AIReadiness, Never>()
    var readinessChanges: AnyPublisher<AIReadiness, Never> { subject.eraseToAnyPublisher() }
    var requests: [AIRequest] = []
    var used = 0
    var delay: TimeInterval = 0.02

    func noteUsed() { used += 1 }

    func complete(_ request: AIRequest, onToken: @escaping @Sendable (String) -> Void,
                  completion: @escaping @Sendable (Result<String, AIError>) -> Void) -> AIGeneration {
        requests.append(request)
        let generation = AIGeneration()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if generation.isCancelled { return completion(.failure(.cancelled)) }
            onToken("FAKE: "); onToken(request.prompt)
            completion(.success("FAKE: " + request.prompt))
        }
        return generation
    }

    func makeSettingsView() -> NSView { NSView() }
}

@MainActor
private func jsBridgeTests() {
    let savedAI = Services.ai
    let savedEnabled = Defaults[.extensionsEnabled]
    defer { Services.ai = savedAI; Defaults[.extensionsEnabled] = savedEnabled }
    Defaults[.extensionsEnabled] = true
    let fake = FakeAI()
    Services.ai = fake
    let user = scratch("bridge")
    defer { try? FileManager.default.removeItem(at: user) }

    // An extension that doesn't declare usesAI can't call AI.complete.
    let plain = user.appendingPathComponent("plain")
    try? FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
    try? #"{"name":"plain","version":"1.0.0"}"#.write(to: plain.appendingPathComponent("extension.json"), atomically: true, encoding: .utf8)
    try? """
    (function () { var e = new Extension({ name: "plain" });
      new Command({ name: "sneak", type: "insert", parameters: [], extension: e, execute: function () { return AI.complete("x"); } }); })();
    """.write(to: plain.appendingPathComponent("index.js"), atomically: true, encoding: .utf8)

    let m = ExtensionsManager(userDirectory: user)
    check(m.failures.isEmpty, "extensions load: \(m.failures.map(\.message))")

    @MainActor func run(_ invocation: String, line: String? = nil, note: String? = nil, statuses: UnsafeMutablePointer<[String]>? = nil,
                        cancelAfter: TimeInterval? = nil) -> ExtensionEdit? {
        var result: ExtensionEdit?
        let line = line ?? invocation
        let run = m.run(invocation: invocation, line: line, note: note ?? line, progress: { p in
            if case .status(let s) = p { statuses?.pointee.append(s) }
        }) { result = $0 }
        if let cancelAfter { DispatchQueue.main.asyncAfter(deadline: .now() + cancelAfter) { run.cancel() } }
        pump(until: { result != nil })
        return result
    }

    check(run("::ask(Three names for a grey cat)") == .insert("FAKE: Three names for a grey cat"), "::ask goes through AI.complete")
    check(fake.used >= 1, "the service hears that an AI command was used")
    check(fake.requests.last?.system.contains("concise assistant") == true && fake.requests.last?.maxTokens == 1024,
          "the llm preferences reach the engine")
    var statuses: [String] = []
    _ = run("::ask(hi)", statuses: &statuses)
    check(statuses == ["Thinking…"], "a Thinking… pill while the answer comes (\(statuses))")
    check(run("::translate(French)", line: "hello ::translate(French)", note: "hello ::translate(French)") == .replaceLine("FAKE: Translate the following text into French. Reply with the translation only.\n\nhello"),
          "::translate builds its prompt from the line")
    check(run("::summarize(2)", line: "::summarize(2)", note: "a\nb\n::summarize(2)") == .insert("FAKE: Summarize the following note in at most 2 sentences:\n\na\nb"),
          "::summarize uses the whole note")
    check(run("::sneak") == .failure("This extension doesn't declare \"usesAI\": true in its extension.json"), "AI.complete needs the manifest flag")

    // Not ready yet: the command waits with the download's pill and runs when the model lands.
    fake.readiness = .preparing("Getting ready… 40%")
    var waitingStatuses: [String] = []
    var waitingResult: ExtensionEdit?
    m.run(invocation: "::ask(later)", line: "::ask(later)", note: "::ask(later)", progress: { p in
        if case .status(let s) = p { waitingStatuses.append(s) }
    }) { waitingResult = $0 }
    pump(until: { false }, seconds: 0.1)
    check(waitingResult == nil && waitingStatuses == ["Getting ready… 40%"], "held back with the progress pill (\(waitingStatuses))")
    fake.readiness = .preparing("Getting ready… 90%")
    pump(until: { waitingStatuses.count == 2 }, seconds: 1)
    check(waitingStatuses == ["Getting ready… 40%", "Getting ready… 90%"], "the pill follows the download (\(waitingStatuses))")
    fake.readiness = .ready
    pump(until: { waitingResult != nil })
    check(waitingResult == .insert("FAKE: later") && waitingStatuses.last == "Thinking…", "ran on its own once ready: \(String(describing: waitingResult))")

    // Not coming: the reason is the failure.
    fake.readiness = .unavailable("Try again when the download finishes.")
    check(run("::ask(x)") == .failure("Try again when the download finishes."), "unavailable says what to do")
    fake.readiness = .preparing("Getting ready…")
    var lost: ExtensionEdit?
    m.run(invocation: "::ask(never)", line: "::ask(never)", note: "::ask(never)", progress: { _ in }) { lost = $0 }
    fake.readiness = .unavailable("The download stopped.")
    pump(until: { lost != nil })
    check(lost == .failure("The download stopped."), "a waiting command hears that the model isn't coming: \(String(describing: lost))")

    // Esc: cancelled while waiting, and cancelled while the engine works.
    fake.readiness = .preparing("Getting ready…")
    check(run("::ask(waiting)", cancelAfter: 0.05) == .message("Stopped"), "cancel while waiting")
    fake.readiness = .ready
    fake.delay = 0.5
    check(run("::ask(slow)", cancelAfter: 0.05) == .message("Stopped"), "cancel during generation")
    fake.delay = 0.02

    // No AI service at all: the command says so.
    Services.ai = nil
    check(run("::ask(x)") == .failure("AI isn't available in this copy of Super Notes"), "no service")
}

// MARK: - Command-line engine over fake executables

@MainActor
private func commandLineTests() {
    let bin = scratch("bin")
    defer { try? FileManager.default.removeItem(at: bin) }
    func install(_ name: String, _ script: String) {
        let url = bin.appendingPathComponent(name)
        try? ("#!/bin/sh\n" + script).write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
    // A codex that honours `exec … -o FILE -`: the prompt on stdin, the answer in the file, noise on stderr.
    install("codex", """
    out=""
    while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift;; esac; shift; done
    prompt=$(cat)
    printf 'ANSWER: %s' "$prompt" > "$out"
    echo "working…" >&2
    """)
    install("claude", "prompt=$(cat); printf 'CLAUDE: %s\\n' \"$prompt\"")
    install("gemini", "sleep 30")
    try? "not executable".write(to: bin.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

    let tools = CommandLineTools.detect(in: [bin, URL(fileURLWithPath: "/nonexistent")])
    check(tools.map(\.name) == ["codex", "claude", "gemini"], "found in kind order (\(tools.map(\.name)))")
    check(CommandLineTools.detect(in: [URL(fileURLWithPath: "/nonexistent")]).isEmpty, "nothing in an empty folder")
    let dirs = CommandLineTools.searchDirectories(path: "/usr/bin:/opt/homebrew/bin", home: URL(fileURLWithPath: "/Users/nobody"))
    check(dirs.prefix(3).map(\.path) == ["/usr/bin", "/opt/homebrew/bin", "/usr/local/bin"] && dirs.contains { $0.path == "/Users/nobody/.local/bin" },
          "PATH first, then the usual places, without repeats (\(dirs.map(\.path)))")
    check(tools[0].label == "Use an installed command-line tool: codex", "plain label")

    let codex = tools[0], claude = tools[1], gemini = tools[2]
    let scratchDir = URL(fileURLWithPath: "/tmp/x")
    let codexCall = CommandLineTools.invocation(for: codex, prompt: "p", scratch: scratchDir)
    check(codexCall.arguments.first == "exec" && codexCall.arguments.contains("--skip-git-repo-check") && codexCall.arguments.contains("read-only")
          && codexCall.arguments.last == "-" && codexCall.standardInput == "p" && codexCall.answerFile?.path == "/tmp/x/answer.txt",
          "codex: exec, read-only sandbox, stdin prompt, answer file")
    let claudeCall = CommandLineTools.invocation(for: claude, prompt: "p", scratch: scratchDir)
    check(claudeCall.arguments.prefix(2) == ["-p", "--output-format"] && claudeCall.arguments.contains("--tools") && claudeCall.standardInput == "p",
          "claude: print mode, no tools, stdin prompt")
    check(CommandLineTools.invocation(for: gemini, prompt: "p", scratch: scratchDir).arguments == ["-p", "p"], "gemini: prompt argument")
    check(CommandLineTools.text(for: AIRequest(prompt: "q", system: "s")) == "s\n\nq", "instructions precede the question")

    @MainActor func run(_ tool: CommandLineTool, _ request: AIRequest, timeout: TimeInterval = 10, cancelAfter: TimeInterval? = nil) -> Result<String, AIError>? {
        nonisolated(unsafe) var result: Result<String, AIError>?
        let generation = CommandLineTools.run(tool, request: request, timeout: timeout) { result = $0 }
        if let cancelAfter { DispatchQueue.main.asyncAfter(deadline: .now() + cancelAfter) { generation.cancel() } }
        pump(until: { result != nil }, seconds: 15)
        return result
    }
    check(run(codex, AIRequest(prompt: "What is 2+2?", system: "Be brief.")) == .success("ANSWER: Be brief.\n\nWhat is 2+2?"), "codex answers through its file")
    check(run(claude, AIRequest(prompt: "hello")) == .success("CLAUDE: hello"), "claude answers on stdout")
    let started = Date()
    check(run(gemini, AIRequest(prompt: "x"), timeout: 1) == .failure(.failed("gemini took longer than 1 seconds")), "a stuck tool times out")
    check(Date().timeIntervalSince(started) < 5, "the timeout ends the wait")
    check(run(gemini, AIRequest(prompt: "x"), timeout: 10, cancelAfter: 0.1) == .failure(.cancelled), "cancel ends the process")

    let service = AIService(downloader: ModelDownloader(spec: ModelCatalog.default, folder: scratch("models"),
                                                        conditions: { DownloadConditions(networkOK: false, lowPowerMode: false, freeDiskBytes: 0) }),
                            tools: tools)
    let savedEngine = Defaults[.aiEngine], savedTool = Defaults[.aiCommandLineTool], savedAuto = Defaults[.aiAutoDownload]
    defer { Defaults[.aiEngine] = savedEngine; Defaults[.aiCommandLineTool] = savedTool; Defaults[.aiAutoDownload] = savedAuto }
    Defaults[.aiEngine] = .commandLine
    Defaults[.aiCommandLineTool] = claude.url.path
    check(service.engine == .commandLine && service.selectedTool == claude && service.readiness == .ready, "the picked tool is ready")
    Defaults[.aiCommandLineTool] = "/gone/tool"
    check(service.selectedTool == codex, "a tool that went away falls back to the first found")
    Defaults[.aiEngine] = .onDevice
    Defaults[.aiAutoDownload] = false
    if case .unavailable(let reason) = service.readiness { check(reason.contains("Settings → AI"), "no model and no download: says where to go") }
    else { check(false, "on-device without a model isn't ready: \(service.readiness)") }
    Defaults[.aiAutoDownload] = true
    service.noteUsed()
    if case .unavailable(let reason) = service.readiness { check(reason.contains("Try again when the download finishes"), "blocked download: \(reason)") }
    else { check(false, "a blocked download isn't ready: \(service.readiness)") }
}

// MARK: - The real model, when a GGUF is at hand

/// Folders a developer points the smoke test at (`SUPERNOTES_DEV_MODELS`, colon-separated), else the installed
/// Models folder (read only). Models are never in the repository.
private var devModelFolders: [URL] {
    if let env = ProcessInfo.processInfo.environment["SUPERNOTES_DEV_MODELS"] {
        return env.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
    }
    return [FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(SuperNotesPaths.supportFolderName + "/Models", isDirectory: true)]
}

@MainActor
private func llamaSmokeTest() {
    check(LlamaEngine.supportsGPUOffload || !ProcessInfo.processInfo.isAppleSilicon, "llama backend initialised (GPU offload \(LlamaEngine.supportsGPUOffload))")
    let missing = LlamaEngine(modelURL: URL(fileURLWithPath: "/nonexistent/model.gguf"))
    do { try missing.load(); check(false, "loading a missing GGUF must throw") } catch { check(error is AIError, "a missing GGUF fails cleanly") }

    let gguf = devModelFolders.flatMap { folder in
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "gguf" }
    }.first
    guard let gguf else { print("  (skipped: no GGUF in the dev model folders)"); return }
    let engine = LlamaEngine(modelURL: gguf)
    let started = Date()
    do { try engine.load() } catch { return check(false, "GGUF load failed: \(error.localizedDescription)") }
    let loaded = Date().timeIntervalSince(started)
    nonisolated(unsafe) var pieces: [String] = []
    nonisolated(unsafe) var result: Result<String, AIError>?
    _ = engine.generate(AIRequest(prompt: "What is 2+2? Reply with just the number.", system: "Answer in plain text.", maxTokens: 32),
                        onToken: { pieces.append($0) }) { result = $0 }
    pump(until: { result != nil }, seconds: 120)
    switch result {
    case .success(let answer)?:
        check(answer.contains("4") && !answer.contains("<think>"), "2+2 answered: '\(answer)'")
        check(!pieces.isEmpty, "the answer streamed in \(pieces.count) pieces")
        print("  llama: \(gguf.lastPathComponent) loaded in \(String(format: "%.2f", loaded)) s; answer '\(answer)' in \(pieces.count) pieces")
    case .failure(let error)?: check(false, "generation failed: \(error.localizedDescription)")
    case nil: check(false, "generation timed out")
    }
    // Esc: a cancelled generation stops with the cancelled error.
    nonisolated(unsafe) var cancelled: Result<String, AIError>?
    let generation = engine.generate(AIRequest(prompt: "Write a long story about a cat.", maxTokens: 400), onToken: { _ in }) { cancelled = $0 }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { generation.cancel() }
    pump(until: { cancelled != nil }, seconds: 60)
    check(cancelled == .failure(.cancelled), "cancel stops decoding: \(String(describing: cancelled))")
    engine.unload()
    check(!engine.isLoaded, "unloaded")
}

private extension ProcessInfo {
    var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }
}
