import Foundation
import Network

/// The Mac's network, power and disk state, with a callback when any of it changes.
final class SystemConditions: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var path: NWPath?
    private var observer: NSObjectProtocol?
    private let folder: URL
    /// Called on the main queue after a change.
    var onChange: (@MainActor () -> Void)?

    init(folder: URL) {
        self.folder = folder
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            lock.withLock { self.path = path }
            notify()
        }
        monitor.start(queue: DispatchQueue(label: "supernotes.ai.network"))
        observer = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: nil) {
            [weak self] _ in self?.notify()
        }
    }

    deinit {
        monitor.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func notify() {
        DispatchQueue.main.async { [self] in MainActor.assumeIsolated { onChange?() } }
    }

    var current: DownloadConditions {
        let path = lock.withLock { self.path }
        let networkOK = path.map { $0.status == .satisfied && !$0.isExpensive && !$0.isConstrained } ?? false
        return DownloadConditions(networkOK: networkOK, lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                  freeDiskBytes: Self.freeDisk(at: folder))
    }

    static func freeDisk(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
