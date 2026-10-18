import Foundation
import Combine
import CryptoKit
import SuperNotesCore

/// Fetches one model into `folder` without getting in the way: only on an unmetered, unconstrained network, never
/// in Low Power Mode, never with less than 10 GB free, at low priority. The bytes go to `<file>.partial`, which
/// a later attempt (or launch) resumes with a `Range` request; the finished file is hashed, and only a matching
/// SHA-256 is moved into place. Failures retry with growing gaps; a short disk is looked at again daily.
@MainActor
public final class ModelDownloader: NSObject, ObservableObject {
    public enum State: Equatable, Sendable {
        case notInstalled
        case waiting(DownloadConditions.Blocker)
        case downloading(received: Int64, total: Int64)
        case verifying
        case installed
        /// What went wrong; another attempt is scheduled.
        case failed(String)

        /// The pill while a command waits for the model.
        public var preparingText: String? {
            switch self {
            case .downloading(let received, let total):
                "Getting ready… \(Int(Double(received) / Double(max(1, total)) * 100))%"
            case .verifying: "Getting ready… checking the download"
            default: nil
            }
        }
    }

    public let spec: ModelSpec
    public let folder: URL
    @Published public private(set) var state: State
    /// When the next automatic attempt is due (after a failure or a short disk).
    public private(set) var nextAttempt: Date?
    /// Consecutive failures; the retry gap grows with them.
    public private(set) var failures = 0

    private let conditions: @MainActor () -> DownloadConditions
    private let configuration: URLSessionConfiguration
    private lazy var session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    private let io = DispatchQueue(label: "supernotes.ai.download", qos: .utility)
    private var task: URLSessionDataTask?
    private var handle: FileHandle?
    private var received: Int64 = 0
    private var lastPublished = Date.distantPast
    /// `start()` was asked for and the file hasn't landed; conditions may be holding it.
    private var wanted = false
    private var retryWork: DispatchWorkItem?

    public init(spec: ModelSpec, folder: URL, configuration: URLSessionConfiguration = ModelDownloader.defaultConfiguration,
                conditions: @escaping @MainActor () -> DownloadConditions) {
        self.spec = spec
        self.folder = folder
        self.configuration = configuration
        self.conditions = conditions
        state = FileManager.default.fileExists(atPath: folder.appendingPathComponent(spec.fileName).path) ? .installed : .notInstalled
        super.init()
    }

    /// Low priority, no cache, no cookies; expensive and constrained paths are refused by the system too.
    nonisolated public static var defaultConfiguration: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.allowsExpensiveNetworkAccess = false
        config.allowsConstrainedNetworkAccess = false
        config.networkServiceType = .background
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 60
        return config
    }

    public var fileURL: URL { folder.appendingPathComponent(spec.fileName) }
    public var partialURL: URL { folder.appendingPathComponent(spec.fileName + ".partial") }
    public var installedURL: URL? { FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil }
    public var isInstalled: Bool { installedURL != nil }
    public var isActive: Bool { task != nil }

    // MARK: - Control

    /// Wants the model: downloads now when conditions allow, else waits for them.
    public func start() {
        guard !isInstalled else { state = .installed; return }
        wanted = true
        retryWork?.cancel(); retryWork = nil; nextAttempt = nil
        attempt()
    }

    /// Re-reads the conditions: a running download pauses when they turn bad (the partial file stays), a waiting
    /// one starts when they turn good.
    public func conditionsChanged() {
        guard wanted, !isInstalled else { return }
        if task != nil {
            if let blocker = conditions().blocker { pause(blocker) }
        } else {
            attempt()
        }
    }

    /// Stops wanting the model (the setting was turned off). A partial file is kept for a later start.
    public func stop() {
        wanted = false
        retryWork?.cancel(); retryWork = nil; nextAttempt = nil
        cancelTask()
        if !isInstalled { state = .notInstalled }
    }

    /// Deletes the model and any partial download.
    public func remove() {
        stop()
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: partialURL)
        state = .notInstalled
    }

    /// Forgets the retry gap and tries now.
    public func retryNow() {
        failures = 0
        start()
    }

    // MARK: - The attempt

    private func attempt() {
        guard task == nil else { return }
        if let blocker = conditions().blocker {
            state = .waiting(blocker)
            // The network and power monitors call back on their own; a short disk is looked at again daily.
            if blocker == .disk { scheduleRetry(after: Self.diskRetryInterval) }
            return
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: partialURL.path) { fm.createFile(atPath: partialURL.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: partialURL) else {
            return fail("Couldn't write to \(folder.path)")
        }
        received = Int64((try? handle.seekToEnd()) ?? 0)
        if received > spec.bytes { received = 0; try? handle.truncate(atOffset: 0) }
        self.handle = handle
        if received == spec.bytes {
            // A full partial file from an earlier run: only the hash is missing.
            handle.closeFile(); self.handle = nil
            return verify()
        }
        var request = URLRequest(url: spec.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.allowsExpensiveNetworkAccess = false
        request.allowsConstrainedNetworkAccess = false
        request.setValue("SuperNotes", forHTTPHeaderField: "User-Agent")
        if received > 0 { request.setValue("bytes=\(received)-", forHTTPHeaderField: "Range") }
        let task = session.dataTask(with: request)
        task.priority = URLSessionTask.lowPriority
        self.task = task
        state = .downloading(received: received, total: spec.bytes)
        Log.ai.info("Downloading \(self.spec.fileName, privacy: .public) from \(self.spec.host, privacy: .public) (from byte \(self.received))")
        task.resume()
    }

    private func cancelTask() {
        task?.cancel()
        task = nil
        closeHandle()
    }

    private func closeHandle() {
        let handle = self.handle
        self.handle = nil
        io.async { try? handle?.close() }
    }

    private func pause(_ blocker: DownloadConditions.Blocker) {
        cancelTask()
        state = .waiting(blocker)
        Log.ai.info("Download paused: \(blocker.text, privacy: .public)")
    }

    private func fail(_ message: String) {
        cancelTask()
        failures += 1
        state = .failed(message)
        Log.ai.error("Download failed: \(message, privacy: .public)")
        scheduleRetry(after: Self.retryDelay(afterFailures: failures))
    }

    /// 1, 2, 4, 8 … minutes, at most an hour.
    nonisolated public static func retryDelay(afterFailures failures: Int) -> TimeInterval {
        min(3600, 60 * pow(2, Double(max(0, failures - 1))))
    }
    nonisolated public static let diskRetryInterval: TimeInterval = 24 * 3600

    private func scheduleRetry(after delay: TimeInterval) {
        retryWork?.cancel()
        nextAttempt = Date().addingTimeInterval(delay)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.wanted else { return }
                self.nextAttempt = nil
                self.attempt()
            }
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Verifying and installing

    private func verify() {
        state = .verifying
        let partial = partialURL, expected = spec.sha256
        io.async { [weak self] in
            let digest = Self.sha256(of: partial)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.verified(digest == expected) }
            }
        }
    }

    private func verified(_ ok: Bool) {
        guard ok else {
            try? FileManager.default.removeItem(at: partialURL)
            return fail("The download didn't match its SHA-256")
        }
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: fileURL.path) { try fm.removeItem(at: fileURL) }
            try fm.moveItem(at: partialURL, to: fileURL)
        } catch {
            return fail("Couldn't move the model into place: \(error.localizedDescription)")
        }
        wanted = false
        failures = 0
        nextAttempt = nil
        state = .installed
        Log.ai.info("Installed \(self.spec.fileName, privacy: .public)")
    }

    /// Lower-case hex SHA-256 of a file, read in 4 MB pieces.
    public nonisolated static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try? handle.read(upToCount: 4 << 20), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension ModelDownloader: URLSessionDataDelegate {
    nonisolated public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                                       completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        MainActor.assumeIsolated {
            guard dataTask === task, let http = response as? HTTPURLResponse else { return completionHandler(.cancel) }
            switch http.statusCode {
            case 206:
                // The server honoured the range; its start must be where the partial file ends.
                let range = http.value(forHTTPHeaderField: "Content-Range") ?? ""
                let start = range.split(separator: " ").last?.split(separator: "-").first.flatMap { Int64($0) }
                guard start == received else { fail("The server resumed at the wrong byte"); return completionHandler(.cancel) }
                completionHandler(.allow)
            case 200:
                // The whole file, whether or not a range was asked for: start the partial file over.
                guard http.expectedContentLength <= 0 || http.expectedContentLength == spec.bytes else {
                    fail("The server has a file of a different size (\(http.expectedContentLength) bytes)")
                    return completionHandler(.cancel)
                }
                if received > 0 {
                    try? handle?.truncate(atOffset: 0)
                    received = 0
                    state = .downloading(received: 0, total: spec.bytes)
                }
                completionHandler(.allow)
            case 416:
                fail("The server refused the resume range")
                completionHandler(.cancel)
            default:
                fail("HTTP \(http.statusCode) from \(spec.host)")
                completionHandler(.cancel)
            }
        }
    }

    nonisolated public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        MainActor.assumeIsolated {
            guard dataTask === task, let handle else { return }
            received += Int64(data.count)
            guard received <= spec.bytes else { return fail("The server sent more than \(spec.bytes) bytes") }
            io.async { try? handle.write(contentsOf: data) }
            let now = Date()
            if now.timeIntervalSince(lastPublished) > 0.25 || received == spec.bytes {
                lastPublished = now
                state = .downloading(received: received, total: spec.bytes)
            }
        }
    }

    nonisolated public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            guard task === self.task else { return }
            self.task = nil
            // Everything written so far must be on disk before hashing or resuming.
            let handle = self.handle
            self.handle = nil
            io.sync { try? handle?.close() }
            if let error {
                if (error as NSError).code == NSURLErrorCancelled { return }
                return fail(error.localizedDescription)
            }
            guard received == spec.bytes else { return fail("The download stopped at \(received) of \(spec.bytes) bytes") }
            verify()
        }
    }
}
