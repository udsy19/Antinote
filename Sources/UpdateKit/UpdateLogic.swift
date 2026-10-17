import Foundation

// The pure parts of updating: versions, the GitHub release feed, the check schedule and the idle test.

/// A semantic version such as "1.2.0", "v1.3" or "2.0.0-beta.2". Numbers compare numerically (missing parts count as
/// 0, so "1.3" == "1.3.0"); a pre-release sorts before its release, its dot-separated identifiers ordered as
/// SemVer 2.0 orders them. Build metadata ("+5") is ignored.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let numbers: [Int]
    public let preRelease: [String]

    public init?(_ text: String) {
        var core = Substring(text.trimmingCharacters(in: .whitespaces))
        if core.first == "v" || core.first == "V" { core = core.dropFirst() }
        if let plus = core.firstIndex(of: "+") { core = core[..<plus] }
        var pre: [String] = []
        if let dash = core.firstIndex(of: "-") {
            pre = core[core.index(after: dash)...].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard pre.allSatisfy({ !$0.isEmpty }) else { return nil }
            core = core[..<dash]
        }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ ("0"..."9").contains($0) }), let n = Int(part) else { return nil }
            numbers.append(n)
        }
        self.numbers = numbers
        preRelease = pre
    }

    public var description: String {
        numbers.map(String.init).joined(separator: ".") + (preRelease.isEmpty ? "" : "-" + preRelease.joined(separator: "."))
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool { order(a, b) == .orderedSame }
    public static func < (a: AppVersion, b: AppVersion) -> Bool { order(a, b) == .orderedAscending }

    private static func order(_ a: AppVersion, _ b: AppVersion) -> ComparisonResult {
        for i in 0..<max(a.numbers.count, b.numbers.count) {
            let x = i < a.numbers.count ? a.numbers[i] : 0, y = i < b.numbers.count ? b.numbers[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        switch (a.preRelease.isEmpty, b.preRelease.isEmpty) {
        case (true, true): return .orderedSame
        case (true, false): return .orderedDescending
        case (false, true): return .orderedAscending
        case (false, false): break
        }
        for (x, y) in zip(a.preRelease, b.preRelease) where x != y {
            switch (Int(x), Int(y)) {
            case let (m?, n?): return m < n ? .orderedAscending : .orderedDescending
            case (.some, nil): return .orderedAscending      // numeric identifiers sort before alphanumeric ones
            case (nil, .some): return .orderedDescending
            case (nil, nil): return x < y ? .orderedAscending : .orderedDescending
            }
        }
        if a.preRelease.count == b.preRelease.count { return .orderedSame }
        return a.preRelease.count < b.preRelease.count ? .orderedAscending : .orderedDescending
    }
}

/// Why an update check, download or install stopped. Only ever logged.
public enum UpdateError: LocalizedError, Equatable {
    case badFeed
    case http(Int)
    case noDiskImage
    case noChecksum
    case checksumMismatch
    case tool(String)
    case appMissing
    case badSignature
    case otherDeveloper
    case wrongApp(String)
    case wrongVersion(String)
    case cannotReplace(String)

    public var errorDescription: String? {
        switch self {
        case .badFeed: "The release feed couldn't be read."
        case .http(let status): "GitHub answered with HTTP \(status)."
        case .noDiskImage: "The release has no \(ReleaseFeed.stableAsset)."
        case .noChecksum: "The release notes have no SHA-256 for \(ReleaseFeed.stableAsset)."
        case .checksumMismatch: "The download doesn't match the SHA-256 in the release notes."
        case .tool(let message): message
        case .appMissing: "The disk image has no \(UpdateInstaller.appName)."
        case .badSignature: "The update's code signature is missing or broken."
        case .otherDeveloper: "The update isn't signed with the same identity as this copy of Super Notes."
        case .wrongApp(let id): "The update is a different app (\(id))."
        case .wrongVersion(let version): "The update is version \(version), not the one the release advertises."
        case .cannotReplace(let folder): "Super Notes can't replace itself in \(folder)."
        }
    }
}

/// The parts of a GitHub release the updater uses.
public struct ReleaseInfo: Equatable, Sendable {
    public var version: AppVersion
    /// The disk image to download.
    public var diskImage: URL?
    /// The disk image's SHA-256 (lowercase hex) from the release notes.
    public var sha256: String?

    public init(version: AppVersion, diskImage: URL?, sha256: String?) {
        self.version = version; self.diskImage = diskImage; self.sha256 = sha256
    }
}

/// The latest release on GitHub, in the shape `scripts/release.sh` publishes it.
public enum ReleaseFeed {
    public static let github = URL(string: "https://api.github.com/repos/udsy19/super-notes/releases/latest")!
    /// The asset release.sh uploads under a stable name, next to `SuperNotes-<version>.dmg`.
    public static let stableAsset = "SuperNotes.dmg"

    /// The feed the app reads. Debug builds can point it at a local file or server with `SUPERNOTES_UPDATE_FEED` for
    /// testing; release builds always read GitHub.
    static var url: URL {
        #if DEBUG
        if let custom = ProcessInfo.processInfo.environment["SUPERNOTES_UPDATE_FEED"], let url = URL(string: custom) { return url }
        #endif
        return github
    }

    /// Requests carry no cookies and nothing is cached, so every check is anonymous.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let url: URL
            enum CodingKeys: String, CodingKey { case name, url = "browser_download_url" }
        }
        let tag: String
        let body: String?
        let assets: [Asset]
        enum CodingKeys: String, CodingKey { case tag = "tag_name", body, assets }
    }

    /// Reads a `releases/latest` response.
    public static func parse(_ data: Data) throws -> ReleaseInfo {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let version = AppVersion(payload.tag) else { throw UpdateError.badFeed }
        let tag = payload.tag.hasPrefix("v") ? String(payload.tag.dropFirst()) : payload.tag
        return ReleaseInfo(version: version,
                           diskImage: diskImage(in: payload.assets.map { ($0.name, $0.url) }, version: tag),
                           sha256: checksum(in: payload.body ?? ""))
    }

    /// The SHA-256 line release.sh writes into the notes: SHA-256 (SuperNotes.dmg): `<64 hex digits>`.
    public static func checksum(in notes: String) -> String? {
        let pattern = #"SHA-256 \(SuperNotes\.dmg\): `([0-9a-f]{64})`"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: notes, range: NSRange(notes.startIndex..., in: notes)),
              let range = Range(match.range(at: 1), in: notes) else { return nil }
        return String(notes[range])
    }

    /// `SuperNotes.dmg`, or else `SuperNotes-<version>.dmg` (release.sh uploads the same file under both names).
    public static func diskImage(in assets: [(name: String, url: URL)], version: String) -> URL? {
        assets.first { $0.name == stableAsset }?.url ?? assets.first { $0.name == "SuperNotes-\(version).dmg" }?.url
    }

    public static func fetch(from url: URL, userAgent: String) async throws -> ReleaseInfo {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError.http(http.statusCode) }
        return try parse(data)
    }
}

/// What the idle test looks at before Super Notes quits and reopens itself into an update.
public struct IdleState: Sendable {
    /// Seconds since the last keyboard, mouse or trackpad input anywhere on the Mac.
    public var secondsSinceInput: TimeInterval
    public var windowVisible: Bool
    public var windowKey: Bool
    public var timerRunning: Bool
    public var unsavedEdits: Bool

    public init(secondsSinceInput: TimeInterval, windowVisible: Bool, windowKey: Bool, timerRunning: Bool, unsavedEdits: Bool) {
        self.secondsSinceInput = secondsSinceInput; self.windowVisible = windowVisible; self.windowKey = windowKey
        self.timerRunning = timerRunning; self.unsavedEdits = unsavedEdits
    }
}

public enum UpdateSchedule {
    public static let firstCheckDelay: TimeInterval = 60
    public static let checkInterval: TimeInterval = 6 * 3600
    /// Automatic checks are at least this far apart, across relaunches too.
    public static let minimumGap: TimeInterval = 4 * 3600
    public static let idleThreshold: TimeInterval = 10 * 60

    /// Whether a check may start now, given when the last one started (nil: never). A clock set back never blocks it.
    public static func isCheckDue(lastAttempt: Date?, now: Date) -> Bool {
        guard let lastAttempt else { return true }
        let elapsed = now.timeIntervalSince(lastAttempt)
        return elapsed >= minimumGap || elapsed < 0
    }

    /// Whether a staged update may be installed by quitting and reopening now: nobody has touched the Mac for ten
    /// minutes, the note window is hidden or in the background, no timer is counting and every edit is saved.
    public static func canInstallNow(_ state: IdleState) -> Bool {
        state.secondsSinceInput >= idleThreshold && !(state.windowVisible && state.windowKey)
            && !state.timerRunning && !state.unsavedEdits
    }
}
