import Foundation
import CryptoKit
import Security
import SuperNotesCore

/// Downloads and verifies an update, stages it next to the app it replaces, and swaps it in once that app has quit.
public struct UpdateInstaller {
    public static let bundleID = "com.udsy.supernotes"
    public static let appName = "Super Notes.app"
    /// Staged copies are hidden bundles in the folder of the app they replace: `.SuperNotes-update-<version>.app`.
    static let stagingPrefix = ".SuperNotes-update-"

    /// The designated requirement every update must satisfy: the running app's own, so only builds signed with the
    /// same identity are accepted.
    public let requirement: SecRequirement
    public let userAgent: String

    public init(requirement: SecRequirement, userAgent: String) {
        self.requirement = requirement
        self.userAgent = userAgent
    }

    // MARK: - Code signing

    /// The running app's designated requirement. Nil for an unsigned or ad-hoc signed copy, whose requirement names its
    /// own hash and so could never accept an update.
    public static func ownRequirement() -> SecRequirement? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        return stableRequirement(of: staticCode)
    }

    /// The designated requirement of the app at `url` (the self-test checks updates against a built app's).
    public static func designatedRequirement(of url: URL) -> SecRequirement? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        return stableRequirement(of: staticCode)
    }

    private static func stableRequirement(of code: SecStaticCode) -> SecRequirement? {
        var requirement: SecRequirement?
        var text: CFString?
        guard SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess,
              let text = text as String?, !text.contains("cdhash") else { return nil }
        return requirement
    }

    /// Checks that `app` is intact, signed by the same identity as this copy (`requirement`), is Super Notes and is
    /// `version`.
    public func verify(app: URL, version: AppVersion) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { throw UpdateError.badSignature }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        let validity = SecStaticCodeCheckValidity(code, flags, nil)
        guard validity == errSecSuccess else {
            Log.updates.error("Code signature check failed (\(validity, privacy: .public))")
            throw UpdateError.badSignature
        }
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else { throw UpdateError.otherDeveloper }
        // Info.plist is sealed by the signature checked above.
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        let id = info["CFBundleIdentifier"] as? String ?? ""
        guard id == Self.bundleID else { throw UpdateError.wrongApp(id) }
        let found = info["CFBundleShortVersionString"] as? String ?? ""
        guard AppVersion(found) == version else { throw UpdateError.wrongVersion(found) }
    }

    // MARK: - Staging

    public static func stagingURL(replacing target: URL, version: AppVersion) -> URL {
        target.deletingLastPathComponent().appendingPathComponent("\(stagingPrefix)\(version).app", isDirectory: true)
    }

    /// Whether the app at `target` can be swapped for another: its folder and the bundle itself (moving a folder to
    /// a new parent rewrites it) are writable, and it isn't running from a read-only translocated copy.
    public static func canReplace(_ target: URL) -> Bool {
        let fm = FileManager.default
        return !target.path.contains("/AppTranslocation/") && fm.isWritableFile(atPath: target.deletingLastPathComponent().path)
            && fm.isWritableFile(atPath: target.path)
    }

    /// Download → SHA-256 → mount → signature, bundle id and version → copy next to `target` → unmount. Temporary
    /// files are removed whatever happens. Returns the staged app.
    public func stage(_ release: ReleaseInfo, replacing target: URL) async throws -> URL {
        guard let image = release.diskImage else { throw UpdateError.noDiskImage }
        guard let checksum = release.sha256 else { throw UpdateError.noChecksum }
        guard Self.canReplace(target) else { throw UpdateError.cannotReplace(target.deletingLastPathComponent().path) }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("supernotes-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: work)
            Log.updates.info("Removed the temporary download folder")
        }

        let dmg = work.appendingPathComponent(ReleaseFeed.stableAsset)
        Log.updates.info("Downloading \(image.absoluteString, privacy: .public)")
        try await download(image, to: dmg)
        Log.updates.info("Verifying the SHA-256 of the download")
        try Self.verifyChecksum(of: dmg, expected: checksum)

        Log.updates.info("Mounting the disk image")
        let volume = try Self.attach(dmg)
        defer {
            Self.detach(volume)
            Log.updates.info("Unmounted the disk image")
        }
        let app = volume.appendingPathComponent(Self.appName, isDirectory: true)
        guard fm.fileExists(atPath: app.path) else { throw UpdateError.appMissing }
        Log.updates.info("Verifying the code signature, bundle id and version of \(release.version, privacy: .public)")
        try verify(app: app, version: release.version)

        let staged = Self.stagingURL(replacing: target, version: release.version)
        Log.updates.info("Copying the update to \(staged.path, privacy: .public)")
        do {
            if fm.fileExists(atPath: staged.path) { try fm.removeItem(at: staged) }
            try Self.run("/usr/bin/ditto", [app.path, staged.path])
            try verify(app: staged, version: release.version)
        } catch {
            try? fm.removeItem(at: staged)
            throw error
        }
        return staged
    }

    private func download(_ url: URL, to destination: URL) async throws {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (file, response) = try await ReleaseFeed.session.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError.http(http.statusCode) }
        try FileManager.default.moveItem(at: file, to: destination)
    }

    public static func verifyChecksum(of file: URL, expected: String) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard hex == expected.lowercased() else { throw UpdateError.checksumMismatch }
    }

    /// Mounts `dmg` read-only and out of Finder's sight; returns where it was mounted.
    private static func attach(_ dmg: URL) throws -> URL {
        let output = try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-plist", dmg.path])
        guard let plist = try? PropertyListSerialization.propertyList(from: output, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPoint = entities.lazy.compactMap({ $0["mount-point"] as? String }).first
        else { throw UpdateError.tool("hdiutil attach reported no mount point.") }
        return URL(fileURLWithPath: mountPoint, isDirectory: true)
    }

    private static func detach(_ volume: URL) {
        if (try? run("/usr/bin/hdiutil", ["detach", volume.path, "-quiet"])) == nil {
            _ = try? run("/usr/bin/hdiutil", ["detach", volume.path, "-force", "-quiet"])
        }
    }

    /// Runs a command-line tool to completion; returns its standard output, or throws with its standard error.
    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = out
        process.standardError = err
        try process.run()
        // Drain both pipes so a chatty tool can't block on a full one.
        let errors = ErrorOutput()
        let drained = DispatchGroup()
        drained.enter()
        DispatchQueue.global().async {
            errors.data = err.fileHandleForReading.readDataToEndOfFile()
            drained.leave()
        }
        let output = out.fileHandleForReading.readDataToEndOfFile()
        drained.wait()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateError.tool("\((tool as NSString).lastPathComponent) \(arguments.first ?? "") failed: \(message)")
        }
        return output
    }

    private final class ErrorOutput: @unchecked Sendable { var data = Data() }

    // MARK: - Swapping

    /// Starts a detached shell that waits up to 30 s for process `pid` to exit, then moves `target` to `trash`, puts
    /// `staged` in its place (without the quarantine flag) and, with `relaunch`, reopens it in the background. If a
    /// step fails the previous version stays (or is put back). Paths reach the script only as arguments. Its output
    /// is appended to `log`.
    @discardableResult
    public static func startSwap(waitingFor pid: Int32, staged: URL, target: URL, trash: URL, relaunch: Bool,
                                 log: URL) throws -> Process {
        guard staged.lastPathComponent.hasPrefix(stagingPrefix),
              staged.deletingLastPathComponent().standardizedFileURL == target.deletingLastPathComponent().standardizedFileURL
        else { throw UpdateError.tool("The staged update isn't next to the app it replaces.") }
        let fm = FileManager.default
        if !fm.fileExists(atPath: log.path) { fm.createFile(atPath: log.path, contents: nil) }
        let logHandle = try FileHandle(forWritingTo: log)
        defer { try? logHandle.close() }   // the helper keeps its own descriptor
        try logHandle.seekToEnd()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", swapScript, "supernotes-update", String(pid), staged.path, target.path, trash.path,
                             relaunch ? "1" : "0"]
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()   // Process puts the helper in its own process group, so it outlives Super Notes
        return process
    }

    /// $1 pid, $2 staged app, $3 app to replace, $4 Trash folder, $5 reopen afterwards (1/0).
    private static let swapScript = """
        trap '' HUP
        pid=$1 staged=$2 target=$3 trash=$4 relaunch=$5
        say() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
        reopen() { if [ "$relaunch" = 1 ]; then open -n -g "$target" && say "Reopened $target"; fi; }
        case "$staged" in */.SuperNotes-update-*.app) ;; *) say "Unexpected staging path: $staged"; exit 2 ;; esac
        tries=0
        while kill -0 "$pid" 2>/dev/null; do
          tries=$((tries + 1))
          if [ "$tries" -gt 150 ]; then
            say "Super Notes ($pid) didn't quit within 30 seconds; update skipped"; rm -rf "$staged"; exit 1
          fi
          sleep 0.2
        done
        say "Super Notes ($pid) has quit; installing $staged"
        xattr -dr com.apple.quarantine "$staged" 2>/dev/null
        old="$trash/$(basename "$target" .app) $(date '+%Y-%m-%d %H.%M.%S').app"
        if ! mv "$target" "$old"; then
          say "Couldn't move $target to the Trash; update skipped"; rm -rf "$staged"; reopen; exit 1
        fi
        say "Moved the previous version to $old"
        if ! mv "$staged" "$target"; then
          say "Couldn't move the update into place; putting the previous version back"
          mv "$old" "$target"; rm -rf "$staged"; reopen; exit 1
        fi
        say "Installed the update at $target"
        reopen
        exit 0
        """
}
