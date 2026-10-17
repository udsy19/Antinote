import AppKit
import Combine
import SuperNotesCore

extension Defaults.Keys {
    /// When the last check started, in seconds since 1970 (0 = never); checks stay `UpdateSchedule.minimumGap` apart.
    static let updateKitLastAttempt = Key<Double>("updateKit.lastAttempt", default: 0)
    /// The version handed to the swap helper; the first launch of that version says "Updated to …" once.
    static let updateKitInstalledVersion = Key<String>("updateKit.installedVersion", default: "")
}

/// Registers this module (called once at launch).
public enum UpdateKitModule {
    @MainActor public static func install() {
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { Updater.shared.start() }
        }
    }
}

/// Keeps Super Notes up to date without asking: a minute after launch and every six hours (at least four hours apart)
/// it reads the latest GitHub release; a newer version is downloaded, verified and staged next to the app. The staged
/// copy goes in when Super Notes quits, or sooner when the Mac has sat idle: Super Notes then quits and reopens
/// itself in the background. Failures are logged and retried next cycle; the only thing ever shown is a one-time
/// "Updated to …" pill. Settings → Privacy → Install updates automatically turns all of it off.
@MainActor
final class Updater {
    static let shared = Updater()

    private let target = Bundle.main.bundleURL
    private let current = AppVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
    private var installer: UpdateInstaller?
    private var staged: (url: URL, version: AppVersion)?
    private var checking = false
    private var swapStarted = false
    private var checkTimer: Timer?
    private var idleTimer: Timer?
    private var announcement: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []

    func start() {
        guard installer == nil else { return }
        guard let current, Bundle.main.bundleIdentifier == UpdateInstaller.bundleID, target.pathExtension == "app" else {
            Log.updates.info("Not running from the Super Notes app bundle; automatic updates are off")
            return
        }
        guard let requirement = UpdateInstaller.ownRequirement() else {
            Log.updates.info("This copy isn't signed with a stable identity, so no update could be verified; automatic updates are off")
            return
        }
        installer = UpdateInstaller(requirement: requirement, userAgent: "SuperNotes/\(current)")
        removeLeftovers()
        announceIfUpdated(to: current)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { Updater.shared.installOnQuit() }
        }
        Defaults.changes.filter { $0 == Defaults.Keys.installUpdates.name }
            .sink { [weak self] _ in self?.settingChanged() }
            .store(in: &cancellables)
        DispatchQueue.main.asyncAfter(deadline: .now() + UpdateSchedule.firstCheckDelay) {
            MainActor.assumeIsolated {
                Updater.shared.checkIfDue()
                Updater.shared.checkTimer = Timer.scheduledTimer(withTimeInterval: UpdateSchedule.checkInterval, repeats: true) { _ in
                    MainActor.assumeIsolated { Updater.shared.checkIfDue() }
                }
            }
        }
    }

    // MARK: - Checking

    private func checkIfDue() {
        guard Defaults[.installUpdates], !checking, !swapStarted, let installer else { return }
        let last = Defaults[.updateKitLastAttempt]
        guard UpdateSchedule.isCheckDue(lastAttempt: last > 0 ? Date(timeIntervalSince1970: last) : nil, now: Date()) else { return }
        checking = true
        Defaults[.updateKitLastAttempt] = Date().timeIntervalSince1970
        Task {
            defer { checking = false }
            do {
                try await check(with: installer)
            } catch {
                Log.updates.error("Update stopped: \(error.localizedDescription, privacy: .public) Trying again next time.")
            }
        }
    }

    private func check(with installer: UpdateInstaller) async throws {
        Log.updates.info("Checking GitHub for a newer version")
        let release = try await ReleaseFeed.fetch(from: ReleaseFeed.url, userAgent: installer.userAgent)
        Defaults[.lastUpdateCheck] = Date().timeIntervalSince1970
        guard let current, release.version > current else {
            Log.updates.info("Up to date (\(self.current?.description ?? "?", privacy: .public))")
            return
        }
        if staged?.version == release.version { return }
        Log.updates.info("Version \(release.version, privacy: .public) is available")
        let url = try await installer.stage(release, replacing: target)
        guard Defaults[.installUpdates], !swapStarted else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        if let previous = staged, previous.url != url { try? FileManager.default.removeItem(at: previous.url) }
        staged = (url, release.version)
        Log.updates.info("Version \(release.version, privacy: .public) is ready; it installs when Super Notes quits or sits idle")
        idleTimer = idleTimer ?? Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { Updater.shared.installIfIdle() }
        }
    }

    private func settingChanged() {
        if Defaults[.installUpdates] { checkIfDue(); return }
        idleTimer?.invalidate()
        idleTimer = nil
        guard let staged, !swapStarted else { return }
        try? FileManager.default.removeItem(at: staged.url)
        self.staged = nil
        Log.updates.info("Automatic updates turned off; removed the staged update")
    }

    /// Removes staged copies an earlier run left behind (it crashed, or updates were turned off before it quit).
    private func removeLeftovers() {
        let folder = target.deletingLastPathComponent()
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for item in items where item.lastPathComponent.hasPrefix(UpdateInstaller.stagingPrefix) && item.pathExtension == "app" {
            try? FileManager.default.removeItem(at: item)
            Log.updates.info("Removed a leftover staged update: \(item.path, privacy: .public)")
        }
    }

    // MARK: - Installing

    private func installOnQuit() {
        guard let staged, !swapStarted, Defaults[.installUpdates] else { return }
        startSwap(staged, relaunch: false)
    }

    private func installIfIdle() {
        guard let staged, !swapStarted, Defaults[.installUpdates], let windows = Services.windows else { return }
        let state = IdleState(
            secondsSinceInput: CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!),
            windowVisible: windows.isMainWindowVisible, windowKey: windows.isMainWindowKey,
            timerRunning: Services.timers?.hasRunningTimer ?? false, unsavedEdits: windows.hasUnsavedEdits)
        guard UpdateSchedule.canInstallNow(state) else { return }
        Defaults[.updateRelaunch] = state.windowVisible ? .visible : .hidden
        guard startSwap(staged, relaunch: true) else {
            Defaults[.updateRelaunch] = nil
            return
        }
        Log.updates.info("Idle: quitting to install \(staged.version, privacy: .public) and reopening in the background")
        NSApp.terminate(nil)   // the usual quit path saves every note first
    }

    @discardableResult
    private func startSwap(_ staged: (url: URL, version: AppVersion), relaunch: Bool) -> Bool {
        do {
            let fm = FileManager.default
            let trash = try fm.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: target, create: true)
            let log = fm.temporaryDirectory.appendingPathComponent("SuperNotes-update.log")
            try UpdateInstaller.startSwap(waitingFor: ProcessInfo.processInfo.processIdentifier, staged: staged.url,
                                          target: target, trash: trash, relaunch: relaunch, log: log)
            swapStarted = true
            Defaults[.updateKitInstalledVersion] = staged.version.description
            Log.updates.info("Handed \(staged.version, privacy: .public) to the installer; its log is \(log.path, privacy: .public)")
            return true
        } catch {
            Log.updates.error("Couldn't start the installer: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - After an update

    /// The first launch of an installed update says "Updated to <version>" once, when a window next comes forward.
    private func announceIfUpdated(to current: AppVersion) {
        let installed = Defaults[.updateKitInstalledVersion]
        guard !installed.isEmpty else { return }
        Defaults[.updateKitInstalledVersion] = ""
        guard AppVersion(installed) == current else {
            Log.updates.error("The update to \(installed, privacy: .public) didn't go in; see SuperNotes-update.log in the temporary folder")
            return
        }
        Log.updates.info("Now running \(installed, privacy: .public)")
        announcement = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil,
                                                              queue: .main) { note in
            MainActor.assumeIsolated {
                guard (note.object as? NSWindow)?.styleMask.contains(.titled) == true else { return }
                Updater.shared.announce(installed)
            }
        }
    }

    private func announce(_ version: String) {
        guard let announcement else { return }
        NotificationCenter.default.removeObserver(announcement)
        self.announcement = nil
        DispatchQueue.main.async { HUD.show("Updated to \(version)", kind: .success) }
    }
}
