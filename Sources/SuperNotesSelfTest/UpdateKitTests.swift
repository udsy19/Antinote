import Foundation
import CryptoKit
import Security
import SuperNotesCore
import UpdateKit

func registerUpdateKitTests() {
    SelfTest.cases.append(("UpdateKit.versionCompare", {
        func v(_ s: String) -> AppVersion { AppVersion(s)! }
        check(v("1.2.0") < v("1.3.0") && v("1.10.0") > v("1.9.9") && v("2.0.0") > v("1.99.99"), "numeric parts compare as numbers")
        check(v("v1.3") == v("1.3.0") && v("1.3.0+7") == v("1.3.0"), "leading v, missing parts and build metadata")
        check(v("v1.3").description == "1.3" && v("1.3.0-beta.2").description == "1.3.0-beta.2", "description")
        // SemVer 2.0's own precedence example.
        let ordered = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11",
                       "1.0.0-rc.1", "1.0.0"].map(v)
        check(zip(ordered, ordered.dropFirst()).allSatisfy { $0 < $1 }, "pre-releases sort before the release, in SemVer order")
        check(!(v("1.3.0") < v("1.3.0")) && !(v("1.3.0") > v("1.3")), "equal versions are neither newer nor older")
        check(["", "v", "1..2", "1.2.x", "abc", "1.2.3-", "1.2.3-a..b", "+1.2", "1.2.3.4.5"].allSatisfy { AppVersion($0) == nil },
              "malformed versions are rejected")
    }))

    SelfTest.cases.append(("UpdateKit.releaseFeed", {
        let sha = String(repeating: "0123456789abcdef", count: 4)
        let base = "https://github.com/udsy19/super-notes/releases/download/v1.3.0/"
        let release = try? ReleaseFeed.parse(releaseJSON(tag: "v1.3.0", sha: sha, assets: [
            ("SuperNotes-1.3.0.dmg", base + "SuperNotes-1.3.0.dmg"), ("SuperNotes.dmg", base + "SuperNotes.dmg")]))
        check(release?.version == AppVersion("1.3.0"), "tag_name without the v")
        check(release?.diskImage?.absoluteString == base + "SuperNotes.dmg", "the stable asset wins")
        check(release?.sha256 == sha, "SHA-256 from release.sh's notes line")

        func image(_ names: [String]) -> String? {
            ReleaseFeed.diskImage(in: names.map { ($0, URL(string: base + $0)!) }, version: "1.3.0")?.lastPathComponent
        }
        check(image(["Source.zip", "SuperNotes-1.3.0.dmg"]) == "SuperNotes-1.3.0.dmg", "falls back to the versioned asset")
        check(image(["SuperNotes-1.2.0.dmg", "SuperNotes.zip", "Super Notes.dmg"]) == nil, "no matching asset")
        let noImage = try? ReleaseFeed.parse(releaseJSON(tag: "v1.3.0", sha: sha, assets: []))
        check(noImage != nil && noImage?.diskImage == nil, "a release without assets still parses")

        check(ReleaseFeed.checksum(in: "notes\n\nSHA-256 (SuperNotes.dmg): `\(sha)`\n") == sha, "checksum line")
        check(ReleaseFeed.checksum(in: "SHA-256 (SuperNotes.dmg): `\(sha.uppercased())`") == nil, "upper-case hex is not release.sh's")
        check(ReleaseFeed.checksum(in: "SHA-256 (SuperNotes.dmg): `\(sha.dropLast())`") == nil, "63 digits")
        check(ReleaseFeed.checksum(in: "SHA-256 (SuperNotes-1.3.0.dmg): `\(sha)`") == nil, "another file's checksum")
        check(ReleaseFeed.checksum(in: "no checksum here") == nil, "missing line")
        check((try? ReleaseFeed.parse(releaseJSON(tag: "v1.3.0", sha: nil, assets: [])))?.sha256 == nil, "notes without the line")

        func parseError(_ data: Data) -> UpdateError? {
            do { _ = try ReleaseFeed.parse(data); return nil } catch { return error as? UpdateError }
        }
        check(parseError(Data("{\"message\":\"Not Found\"}".utf8)) == .badFeed, "GitHub's error payload")
        check(parseError(releaseJSON(tag: "nightly", sha: sha, assets: [])) == .badFeed, "a tag that isn't a version")
        check(parseError(Data("not json".utf8)) == .badFeed, "not JSON")
    }))

    SelfTest.cases.append(("UpdateKit.schedule", {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func due(_ hoursAgo: Double?) -> Bool {
            UpdateSchedule.isCheckDue(lastAttempt: hoursAgo.map { now.addingTimeInterval(-$0 * 3600) }, now: now)
        }
        check(due(nil), "never checked")
        check(!due(1) && !due(3.9), "less than four hours since the last check")
        check(due(4) && due(6) && due(30), "four hours or more")
        check(due(-2), "a clock set back doesn't block checks")
        check(UpdateSchedule.firstCheckDelay == 60 && UpdateSchedule.checkInterval == 6 * 3600, "a minute after launch, then every six hours")
    }))

    SelfTest.cases.append(("UpdateKit.idleGate", {
        let idle = IdleState(secondsSinceInput: 600, windowVisible: false, windowKey: false, timerRunning: false, unsavedEdits: false)
        func gate(_ change: (inout IdleState) -> Void) -> Bool {
            var state = idle
            change(&state)
            return UpdateSchedule.canInstallNow(state)
        }
        check(UpdateSchedule.canInstallNow(idle), "hidden window, ten idle minutes, nothing running")
        check(!gate { $0.secondsSinceInput = 599 }, "input in the last ten minutes")
        check(gate { $0.secondsSinceInput = 7200 }, "long idle")
        check(gate { $0.windowVisible = true }, "window on screen but in the background")
        check(!gate { $0.windowVisible = true; $0.windowKey = true }, "window in front with focus")
        check(!gate { $0.timerRunning = true }, "a running timer")
        check(!gate { $0.unsavedEdits = true }, "edits not saved yet")
        check(!gate { $0.windowVisible = true; $0.unsavedEdits = true }, "background window with unsaved edits")
    }))

    SelfTest.cases.append(("UpdateKit.endToEnd", { MainActor.assumeIsolated { endToEndUpdate() } }))
}

/// A `releases/latest` payload as GitHub returns it for a release made by scripts/release.sh.
private func releaseJSON(tag: String, sha: String?, assets: [(name: String, url: String)]) -> Data {
    var body = "### Added\n- Automatic updates.\n\n**Install:** `curl -fsSL https://udsy19.github.io/super-notes/install.sh | bash`"
        + " — or download the DMG below."
    if let sha { body += "\n\nSHA-256 (SuperNotes.dmg): `\(sha)`" }
    let object: [String: Any] = [
        "url": "https://api.github.com/repos/udsy19/super-notes/releases/1",
        "html_url": "https://github.com/udsy19/super-notes/releases/tag/\(tag)",
        "tag_name": tag, "name": "Super Notes \(tag)", "draft": false, "prerelease": false, "body": body,
        "assets": assets.map { ["name": $0.name, "browser_download_url": $0.url, "content_type": "application/x-apple-diskimage"] },
    ]
    return try! JSONSerialization.data(withJSONObject: object)
}

/// Runs async work to completion while the main run loop keeps turning.
@MainActor
private func complete<T>(_ seconds: TimeInterval = 120, _ work: @escaping @MainActor () async throws -> T) -> Result<T, Error>? {
    var result: Result<T, Error>?
    Task { @MainActor in
        do { result = .success(try await work()) } catch { result = .failure(error) }
    }
    let deadline = Date().addingTimeInterval(seconds)
    while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    return result
}

private func failure<T>(_ result: Result<T, Error>?) -> UpdateError? {
    if case .failure(let error)? = result { return error as? UpdateError }
    return nil
}

@discardableResult
private func tool(_ path: String, _ arguments: String...) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    guard (try? process.run()) != nil else { return (-1, "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

/// A TCP port nothing is listening on right now.
private func freePort() -> UInt16? {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let bound = withUnsafeMutablePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) == 0 && getsockname(fd, $0, &length) == 0 }
    }
    return bound ? UInt16(bigEndian: address.sin_port) : nil
}

private func shortVersion(_ app: URL) -> String {
    (NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String) ?? ""
}

/// Download → checksum → mount → signature → stage → swap, against the real build/Super Notes.app served from a
/// local web server, in temporary folders, with an already-exited process standing in for the running app and no
/// relaunch.
@MainActor
private func endToEndUpdate() {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let built = root.appendingPathComponent("build/Super Notes.app", isDirectory: true)
    guard fm.fileExists(atPath: built.appendingPathComponent("Contents/Info.plist").path) else {
        print("  (skipped: build/Super Notes.app not found; run scripts/build-app.sh first)"); return
    }
    guard let requirement = UpdateInstaller.designatedRequirement(of: built) else {
        print("  (skipped: build/Super Notes.app is ad-hoc signed; run scripts/signing-setup.sh, then scripts/build-app.sh)"); return
    }
    guard let version = AppVersion(shortVersion(built)) else { check(false, "build/Super Notes.app has a version"); return }
    guard fm.fileExists(atPath: "/usr/bin/python3"), let port = freePort() else {
        print("  (skipped: python3 or a free local port is unavailable)"); return
    }

    let temp = fm.temporaryDirectory
    let tempBefore = Set((try? fm.contentsOfDirectory(atPath: temp.path)) ?? [])
    let work = temp.appendingPathComponent("supernotes-selftest-update-\(UUID().uuidString)", isDirectory: true)
    let serve = work.appendingPathComponent("serve"), image = work.appendingPathComponent("image")
    let apps = work.appendingPathComponent("Applications"), trash = work.appendingPathComponent("Trash")
    for folder in [serve, image, apps, trash] { try? fm.createDirectory(at: folder, withIntermediateDirectories: true) }
    defer { try? fm.removeItem(at: work) }

    // The disk image release.sh would publish, holding this build.
    tool("/usr/bin/ditto", built.path, image.appendingPathComponent(UpdateInstaller.appName).path)
    let dmg = serve.appendingPathComponent("SuperNotes.dmg")
    let created = tool("/usr/bin/hdiutil", "create", "-volname", "Super Notes \(version)", "-srcfolder", image.path,
                       "-fs", "HFS+", "-format", "UDZO", "-ov", dmg.path)
    guard created.status == 0, let dmgData = try? Data(contentsOf: dmg) else { check(false, "hdiutil create: \(created.output)"); return }
    let sha = SHA256.hash(data: dmgData).map { String(format: "%02x", $0) }.joined()

    // A local web server for the feed and the disk image; only this process is stopped afterwards.
    let server = Process()
    server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    server.arguments = ["-I", "-m", "http.server", String(port), "--bind", "127.0.0.1", "--directory", serve.path]
    server.currentDirectoryURL = work
    server.standardOutput = FileHandle.nullDevice
    server.standardError = FileHandle.nullDevice
    guard (try? server.run()) != nil else { check(false, "python3 http.server starts"); return }
    defer {
        server.terminate()
        server.waitUntilExit()
    }
    let base = "http://127.0.0.1:\(port)/"
    try? releaseJSON(tag: "v\(version)", sha: sha, assets: [("SuperNotes-\(version).dmg", base + "nothing-here.dmg"),
                                                            ("SuperNotes.dmg", base + "SuperNotes.dmg")])
        .write(to: serve.appendingPathComponent("latest.json"))

    // The installed copy the update replaces: a stand-in that reports version 0.0.1.
    let target = apps.appendingPathComponent(UpdateInstaller.appName, isDirectory: true)
    try? fm.createDirectory(at: target.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    (["CFBundleIdentifier": UpdateInstaller.bundleID, "CFBundleShortVersionString": "0.0.1"] as NSDictionary)
        .write(to: target.appendingPathComponent("Contents/Info.plist"), atomically: true)

    let installer = UpdateInstaller(requirement: requirement, userAgent: "SuperNotes/self-test")
    var feed: ReleaseInfo?
    for _ in 0..<50 where feed == nil {   // the server needs a moment to start listening
        if case .success(let release)? = complete(5, { try await ReleaseFeed.fetch(from: URL(string: base + "latest.json")!,
                                                                                 userAgent: installer.userAgent) }) {
            feed = release
        } else {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
    }
    guard let release = feed else { check(false, "the feed is served over HTTP"); return }
    check(release.version == version && release.sha256 == sha && release.diskImage?.absoluteString == base + "SuperNotes.dmg",
          "feed read over HTTP")
    let staged = UpdateInstaller.stagingURL(replacing: target, version: version)

    // Refusals: nothing is staged and the download is deleted.
    var wrongSum = release
    wrongSum.sha256 = String(repeating: "0", count: 64)
    check(failure(complete { try await installer.stage(wrongSum, replacing: target) }) == .checksumMismatch, "checksum mismatch refused")
    var noSum = release
    noSum.sha256 = nil
    check(failure(complete { try await installer.stage(noSum, replacing: target) }) == .noChecksum, "missing checksum refused")
    var missing = release
    missing.diskImage = URL(string: base + "nothing-here.dmg")
    check(failure(complete { try await installer.stage(missing, replacing: target) }) == .http(404), "missing download refused")
    check(!fm.fileExists(atPath: staged.path), "nothing staged after a refusal")

    // Signature, bundle and version checks on their own.
    func refusal(_ body: () throws -> Void) -> UpdateError? {
        do { try body(); return nil } catch { return error as? UpdateError }
    }
    check(refusal { try installer.verify(app: built, version: version) } == nil, "the build passes its own checks")
    check(refusal { try installer.verify(app: built, version: AppVersion("99.0")!) } == .wrongVersion(version.description),
          "advertised version must match the bundle")
    var other: SecRequirement?
    SecRequirementCreateWithString(#"identifier "com.example.other""# as CFString, [], &other)
    if let other {
        let stranger = UpdateInstaller(requirement: other, userAgent: "")
        check(refusal { try stranger.verify(app: built, version: version) } == .otherDeveloper, "another signer's requirement")
    }
    let tampered = work.appendingPathComponent("tampered/\(UpdateInstaller.appName)")
    tool("/usr/bin/ditto", built.path, tampered.path)
    if let handle = try? FileHandle(forWritingTo: tampered.appendingPathComponent("Contents/Info.plist")) {
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data("\n".utf8))
        try? handle.close()
    }
    check(refusal { try installer.verify(app: tampered, version: version) } == .badSignature, "a modified bundle is refused")

    // The real thing.
    let staging = complete { try await installer.stage(release, replacing: target) }
    switch staging {
    case .success(let url)?: check(url == staged && fm.fileExists(atPath: staged.path), "staged next to the app")
    case .failure(let error)?: check(false, "staging failed: \(error.localizedDescription)"); return
    case nil: check(false, "staging timed out"); return
    }
    check(!tool("/usr/bin/hdiutil", "info").output.contains("/supernotes-update-"), "disk image unmounted")
    let tempAfter = Set((try? fm.contentsOfDirectory(atPath: temp.path)) ?? [])
    check(tempAfter.subtracting(tempBefore).allSatisfy { !$0.hasPrefix("supernotes-update-") }, "download folder removed")

    // Swap, standing in an already-exited process for Super Notes.
    let exited = Process()
    exited.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try? exited.run()
    exited.waitUntilExit()
    let log = work.appendingPathComponent("update.log")
    guard let helper = try? UpdateInstaller.startSwap(waitingFor: exited.processIdentifier, staged: staged, target: target,
                                                      trash: trash, relaunch: false, log: log) else {
        check(false, "swap helper starts"); return
    }
    helper.waitUntilExit()
    check(helper.terminationStatus == 0, "swap helper succeeded")
    check(shortVersion(target) == shortVersion(built) && refusal { try installer.verify(app: target, version: version) } == nil,
          "the update is in place, signature intact")
    check(!fm.fileExists(atPath: staged.path), "staged copy moved")
    let trashed = (try? fm.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)) ?? []
    check(trashed.count == 1 && shortVersion(trashed[0]) == "0.0.1", "previous version in the Trash")
    let lines = (try? String(contentsOf: log, encoding: .utf8))?.split(separator: "\n") ?? []
    for line in lines { print("  helper: \(line.replacingOccurrences(of: work.path, with: "<tmp>"))") }
}
