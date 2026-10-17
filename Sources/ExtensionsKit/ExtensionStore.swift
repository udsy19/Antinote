import Foundation
import Combine
import JotterCore

extension Defaults.Keys {
    static let extensionsDisabled = Key<Set<String>>("extensions.disabled", default: [])
    /// Known API key ids ("apikey_openai"); the secrets live in the Keychain under the same account name.
    static let extensionsAPIKeys = Key<[String]>("extensions.apiKeys", default: [])
    /// Key id → extension names allowed to use it.
    static let extensionsKeyGrants = Key<[String: [String]]>("extensions.keyGrants", default: [:])
    /// Extension name → GitHub repository it was installed from.
    static let extensionsSources = Key<[String: String]>("extensions.sources", default: [:])

    static func extensionPrefs(_ name: String) -> Key<[String: JSONValue]> {
        Key<[String: JSONValue]>("extensions.prefs.\(name)", default: [:])
    }
}

/// Persistent per-extension state. Thread-safe (UserDefaults + Keychain), so the JS queues read it directly.
public enum ExtensionStore {
    public static func isEnabled(_ name: String) -> Bool { !Defaults[.extensionsDisabled].contains(name) }
    public static func setEnabled(_ enabled: Bool, _ name: String) {
        if enabled { Defaults[.extensionsDisabled].remove(name) } else { Defaults[.extensionsDisabled].insert(name) }
    }

    public static func preference(_ name: String, _ key: String) -> JSONValue? { Defaults[.extensionPrefs(name)][key] }
    public static func setPreference(_ name: String, _ key: String, _ value: JSONValue?) {
        Defaults[.extensionPrefs(name)][key] = value
    }

    // MARK: API keys

    public static var keyIDs: [String] { Defaults[.extensionsAPIKeys] }
    public static func secret(_ id: String) -> String? { Keychain.get(APIKeyID.normalize(id)) }

    /// Adds or replaces a key. New keys are granted to every extension that declares them.
    public static func setKey(_ id: String, secret: String, declaredBy: [String]) {
        let id = APIKeyID.normalize(id)
        Keychain.set(secret, for: id)
        if !Defaults[.extensionsAPIKeys].contains(id) {
            Defaults[.extensionsAPIKeys].append(id)
            Defaults[.extensionsKeyGrants][id] = declaredBy
        }
    }

    public static func deleteKey(_ id: String) {
        Keychain.set(nil, for: id)
        Defaults[.extensionsAPIKeys].removeAll { $0 == id }
        Defaults[.extensionsKeyGrants][id] = nil
    }

    public static func grants(_ id: String) -> [String] { Defaults[.extensionsKeyGrants][APIKeyID.normalize(id)] ?? [] }
    public static func setGrant(_ granted: Bool, key id: String, extension name: String) {
        var list = grants(id).filter { $0 != name }
        if granted { list.append(name) }
        Defaults[.extensionsKeyGrants][APIKeyID.normalize(id)] = list.isEmpty ? nil : list
    }
}

/// Console output and load problems, newest last. `console.*` output is recorded only while
/// `Defaults[.extensionLogging]` is on; load errors always are.
@MainActor
public final class ExtensionLogger: ObservableObject {
    public struct Entry: Identifiable, Sendable {
        public enum Level: String, Sendable { case info, warning, error }
        public let id = UUID()
        public let date: Date
        public let extensionName: String
        public let level: Level
        public let message: String
    }

    public static let shared = ExtensionLogger()
    @Published public private(set) var entries: [Entry] = []
    private let maxEntries = 500

    public func clear() { entries.removeAll() }

    public func append(_ entry: Entry) {
        entries.append(entry)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
    }

    /// Callable from any thread.
    public nonisolated static func log(_ name: String, _ level: Entry.Level, _ message: String, always: Bool = false) {
        guard always || Defaults[.extensionLogging] else { return }
        Log.extensions.log("[\(name, privacy: .public)] \(message, privacy: .public)")
        let entry = Entry(date: Date(), extensionName: name, level: level, message: message)
        DispatchQueue.main.async { MainActor.assumeIsolated { shared.append(entry) } }
    }
}
