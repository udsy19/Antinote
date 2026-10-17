import AppKit
import SwiftUI
import SuperNotesCore

/// The time extensions see through `now()`; tests pin it.
public final class ExtensionClock: @unchecked Sendable {
    private let lock = NSLock()
    private var fixedDate: Date?
    public var fixed: Date? {
        get { lock.withLock { fixedDate } }
        set { lock.withLock { fixedDate = newValue } }
    }
    public func now() -> Date { fixed ?? Date() }
}

/// Loads extensions, resolves `::` invocations and runs them. `Services.extensions`.
@MainActor
public final class ExtensionsManager: ObservableObject, ExtensionsServicing {
    public struct Installed: Identifiable {
        public var id: String { manifest.name }
        public let manifest: ExtensionManifest
        public let folder: URL
        public let isBundled: Bool
        public let commands: [CommandSpec]
        public let preferences: [PreferenceSpec]
        let runtime: ExtensionRuntime
    }

    public struct Failure: Identifiable {
        public var id: String { folder.path }
        public let folder: URL
        public let message: String
    }

    @Published public private(set) var installed: [Installed] = []
    @Published public private(set) var failures: [Failure] = []
    /// Bumped when enablement or keys change so views refresh.
    @Published public private(set) var revision = 0

    public let bundledDirectory: URL?
    public let userDirectory: URL
    public let clock = ExtensionClock()

    public init(bundledDirectory: URL? = ExtensionsManager.bundledExtensionsURL, userDirectory: URL = SuperNotesPaths.extensions) {
        self.bundledDirectory = bundledDirectory
        self.userDirectory = userDirectory
        reload()
    }

    /// `Bundled/` inside the module's resource bundle: the packaged app's Resources first, then next to the
    /// executable (`swift run`, self-tests). Never touches `Bundle.module`, which traps when the bundle is missing.
    public nonisolated static var bundledExtensionsURL: URL? {
        let bundleName = "SuperNotes_ExtensionsKit.bundle"
        var candidates = [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap { $0?.appendingPathComponent(bundleName) }
        if let exe = Bundle.main.executableURL { candidates.append(exe.deletingLastPathComponent().appendingPathComponent(bundleName)) }
        for candidate in candidates {
            if let bundled = Bundle(url: candidate)?.url(forResource: "Bundled", withExtension: nil) { return bundled }
            let direct = candidate.appendingPathComponent("Bundled")
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
        }
        return nil
    }

    // MARK: Loading

    public func reload() {
        var candidates: [String: (manifest: ExtensionManifest, folder: URL, bundled: Bool)] = [:]
        var failures: [Failure] = []

        for (directory, bundled) in [(bundledDirectory, true), (userDirectory, false)] {
            guard let directory else { continue }
            let folders = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                                                                          options: .skipsHiddenFiles)) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for folder in folders {
                do {
                    let manifest = try ExtensionManifest.load(from: folder)
                    if let existing = candidates[manifest.name], existing.bundled == bundled {
                        throw ExtensionError.manifest("Another extension named '\(manifest.name)' is already installed")
                    }
                    candidates[manifest.name] = (manifest, folder, bundled)   // a user copy replaces the bundled one
                } catch {
                    failures.append(Failure(folder: folder, message: error.localizedDescription))
                }
            }
        }

        let graph = candidates.mapValues(\.manifest.dependencyNames)
        let resolution = DependencyResolver.resolve(graph)
        for (name, message) in resolution.errors.sorted(by: { $0.key < $1.key }) {
            failures.append(Failure(folder: candidates[name]!.folder, message: message))
        }

        var loaded: [String: Installed] = [:]
        var order: [Installed] = []
        for name in resolution.order {
            let candidate = candidates[name]!
            let deps = DependencyResolver.closure(of: name, in: graph, order: resolution.order)
            do {
                if let failed = deps.first(where: { loaded[$0] == nil }) {
                    throw ExtensionError.dependency("'\(name)' depends on '\(failed)', which failed to load")
                }
                var scripts: [(file: String, source: String)] = []
                for owner in deps.map({ candidates[$0]! }) + [candidate] {
                    for file in owner.manifest.scriptFiles {
                        let url = owner.folder.appendingPathComponent(file)
                        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                            throw ExtensionError.script("Could not read \(owner.manifest.name)/\(file)")
                        }
                        scripts.append(("\(owner.manifest.name)/\(file)", source))
                    }
                }
                let policy = NetworkPolicy(endpoints: ([name] + deps).flatMap { candidates[$0]!.manifest.endpointList },
                                           keyOwners: [name] + deps)
                let clock = self.clock
                let (runtime, registered) = try ExtensionRuntime.load(name: name, scripts: scripts, policy: policy,
                                                                     clock: { clock.now() })
                guard let own = registered.first(where: { $0.name == name }) else {
                    let names = registered.map(\.name).filter { !deps.contains($0) }
                    throw ExtensionError.script(names.isEmpty ? "index.js does not register an Extension"
                        : "index.js registers '\(names[0])' but extension.json says '\(name)'")
                }
                let item = Installed(manifest: candidate.manifest, folder: candidate.folder, isBundled: candidate.bundled,
                                     commands: own.commands, preferences: own.preferences, runtime: runtime)
                loaded[name] = item
                order.append(item)
            } catch {
                failures.append(Failure(folder: candidate.folder, message: error.localizedDescription))
            }
        }

        for failure in failures {
            ExtensionLogger.log(failure.folder.lastPathComponent, .error, failure.message, always: true)
        }
        installed = order.sorted { $0.manifest.name < $1.manifest.name }
        self.failures = failures
        revision += 1
    }

    // MARK: Enablement

    public func isEnabled(_ name: String) -> Bool { ExtensionStore.isEnabled(name) }
    public func setEnabled(_ enabled: Bool, _ name: String) {
        ExtensionStore.setEnabled(enabled, name)
        revision += 1
    }
    func touch() { revision += 1 }

    private var active: [Installed] {
        guard Defaults[.extensionsEnabled] else { return [] }
        return installed.filter { isEnabled($0.manifest.name) }
    }

    // MARK: ExtensionsServicing

    public var commands: [ExtensionCommandInfo] {
        var seen = Set<String>()
        return active.flatMap { ext in
            ext.commands.compactMap { spec -> ExtensionCommandInfo? in
                guard seen.insert(spec.name.lowercased()).inserted else { return nil }
                return ExtensionCommandInfo(name: spec.name, aliases: spec.aliases, extensionName: ext.manifest.name,
                                            helpText: spec.helpText, signature: spec.signature, action: spec.type.rawValue)
            }
        }
    }

    public func complete(_ prefix: String) -> [ExtensionCommandInfo] {
        var query = prefix.trimmingCharacters(in: .whitespaces).lowercased()
        if query.hasPrefix("::") { query.removeFirst(2) }
        if let paren = query.firstIndex(of: "(") { query = String(query[..<paren]) }
        let ranked = commands.compactMap { info -> (Int, ExtensionCommandInfo)? in
            let name = info.name.lowercased(), aliases = info.aliases.map { $0.lowercased() }
            let rank: Int
            if query.isEmpty { rank = 3 }
            else if name == query || aliases.contains(query) { rank = 0 }
            else if name.hasPrefix(query) { rank = 1 }
            else if aliases.contains(where: { $0.hasPrefix(query) }) { rank = 2 }
            else if name.contains(query) { rank = 3 }
            else { return nil }
            return (rank, info)
        }
        return ranked.sorted { a, b in
            a.0 != b.0 ? a.0 < b.0 : a.1.name.count != b.1.name.count ? a.1.name.count < b.1.name.count : a.1.name < b.1.name
        }.map(\.1)
    }

    /// The enabled command (and its extension) for a name or alias.
    func resolve(_ name: String) -> (Installed, CommandSpec)? {
        let key = name.lowercased()
        for ext in active { if let c = ext.commands.first(where: { $0.name.lowercased() == key }) { return (ext, c) } }
        for ext in active { if let c = ext.commands.first(where: { $0.aliases.contains { $0.lowercased() == key } }) { return (ext, c) } }
        return nil
    }

    public func run(invocation: String, line: String, note: String, completion: @escaping (ExtensionEdit) -> Void) {
        guard Defaults[.extensionsEnabled] else {
            return completion(.failure("Extensions are turned off. Turn them on in Settings → Extensions."))
        }
        let parsed: ExtensionInvocation
        do { parsed = try ExtensionInvocation.parse(invocation) } catch {
            return completion(.failure(error.localizedDescription))
        }
        guard let (ext, spec) = resolve(parsed.name) else { return completion(.failure("Unknown command ::\(parsed.name)")) }
        let values: [JSONValue]
        do {
            values = try parsed.coerced(for: spec) { expression in
                Services.analyzer.map { $0.evaluate(expression) } ?? .failure(ExtensionError.script("Math is unavailable"))
            }
        } catch {
            return completion(.failure(error.localizedDescription))
        }
        let scope = ext.manifest.scope
        let text = ScopedText(invocation: invocation.trimmingCharacters(in: .whitespacesAndNewlines), line: line, note: note, scope: scope)
        let payload: [String: Any] = [
            "parameters": values.map(\.foundation), "line": text.line, "fullText": text.fullText,
            "command": spec.name, "dataScope": scope.rawValue,
        ]
        let type = spec.type
        nonisolated(unsafe) let deliver = completion
        ext.runtime.execute(command: spec.name, extensionName: ext.manifest.name, payload: payload) { result in
            MainActor.assumeIsolated { deliver(Self.edit(for: result, type: type)) }
        }
    }

    static func edit(for result: CommandResult, type: CommandType) -> ExtensionEdit {
        switch result.status.lowercased() {
        case "success", "ok": break
        case "info", "message": return .message(result.message)
        default: return .failure(result.message.isEmpty ? "The command failed" : result.message)
        }
        switch type {
        case .insert: return result.payload.isEmpty ? .message(result.message) : .insert(result.payload)
        case .replaceLine: return .replaceLine(result.payload)
        case .replaceAll: return .replaceAll(result.payload)
        case .openURL:
            let raw = result.payload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: raw), url.scheme != nil else { return .failure("'\(raw)' is not a valid URL") }
            return .openURL(url)
        }
    }

    public func makeSettingsView() -> NSView {
        NSHostingView(rootView: ExtensionsSettingsView(manager: self))
    }
}
