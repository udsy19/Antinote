import Foundation
import Security
import SuperNotesCore

/// One-time move of what the app kept under its previous name, Jotter (before 1.2.0): the Application Support
/// folder, the iCloud Drive sync folder, the preferences and the Keychain items (sync key, API keys). Nothing is
/// deleted: a folder moves only when its new location doesn't exist yet (otherwise both are left as they are),
/// preferences are copied only into an empty domain, and a Keychain item moves only when the new service has none
/// for its account.
public enum LegacyMigration {
    static let oldName = "Jotter"
    static let oldBundleID = "com.udsy.jotter"

    /// The old folder for a new one: same parent, old name.
    public static func legacyFolder(for folder: URL) -> URL {
        folder.deletingLastPathComponent().appendingPathComponent(oldName, isDirectory: true)
    }

    /// Moves `from` to `to` when `from` exists and `to` doesn't; returns whether it moved.
    @discardableResult public static func moveFolder(from: URL, to: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { return false }
        do {
            try fm.moveItem(at: from, to: to)
            return true
        } catch {
            Log.store.error("moving \(from.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// The preferences to write into the new domain, or nil to leave it alone: the old domain's values (with window
    /// frame names like "NSWindow Frame JotterMainWindow" renamed) when the new domain has nothing but AppKit's keys.
    public static func migratedDefaults(old: [String: Any], new: [String: Any]) -> [String: Any]? {
        guard !old.isEmpty, new.keys.allSatisfy({ $0.hasPrefix("NS") || $0.hasPrefix("Apple") }) else { return nil }
        var merged = new
        for (key, value) in old {
            let renamed = key.replacingOccurrences(of: oldName, with: "SuperNotes")
            if merged[renamed] == nil { merged[renamed] = value }
        }
        return merged
    }

    /// Keychain services whose items move, as (old, new): `Keychain` (API keys, upload secrets) and the sync key.
    public static func keychainServices(bundleID: String) -> [(from: String, to: String)] {
        [(oldBundleID, bundleID), (oldBundleID + ".sync", bundleID + ".sync")]
    }

    /// Runs before anything reads preferences or opens the notes database, and only on the first launch under the new
    /// name (no support folder yet), so a later preferences reset or a declined Keychain prompt never repeats it.
    public static func run() {
        let support = SuperNotesPaths.base.appendingPathComponent(SuperNotesPaths.supportFolderName, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: support.path) else { return }
        let defaults = Defaults.store
        if let domain = Bundle.main.bundleIdentifier,
           let old = defaults.persistentDomain(forName: oldBundleID),
           let merged = migratedDefaults(old: old, new: defaults.persistentDomain(forName: domain) ?? [:]) {
            defaults.setPersistentDomain(merged, forName: domain)
        }
        moveFolder(from: legacyFolder(for: support), to: support)
        // iCloud Drive is only touched when sync was in use.
        if Defaults[.syncNotes] || Defaults[.syncPreferences] || Defaults[.syncExtensions] {
            moveFolder(from: legacyFolder(for: ICloudDriveSync.defaultRoot), to: ICloudDriveSync.defaultRoot)
        }
        for (from, to) in keychainServices(bundleID: SuperNotesPaths.bundleID) { moveKeychainItems(from: from, to: to) }
    }

    private static func moveKeychainItems(from old: String, to new: String) {
        for dataProtection in [false, true] {
            func query(_ service: String, _ account: String? = nil) -> [String: Any] {
                var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                        kSecAttrSynchronizable as String: kSecAttrSynchronizableAny]
                if let account { q[kSecAttrAccount as String] = account }
                if dataProtection { q[kSecUseDataProtectionKeychain as String] = true }
                return q
            }
            var list = query(old)
            list[kSecMatchLimit as String] = kSecMatchLimitAll
            list[kSecReturnAttributes as String] = true
            var found: CFTypeRef?
            guard SecItemCopyMatching(list as CFDictionary, &found) == errSecSuccess,
                  let items = found as? [[String: Any]] else { continue }
            for item in items {
                guard let account = item[kSecAttrAccount as String] as? String,
                      SecItemCopyMatching(query(new, account) as CFDictionary, nil) == errSecItemNotFound else { continue }
                var read = query(old, account)
                read[kSecReturnData as String] = true
                var secret: CFTypeRef?
                guard SecItemCopyMatching(read as CFDictionary, &secret) == errSecSuccess, let data = secret as? Data else { continue }
                var add = query(new, account)
                add[kSecAttrSynchronizable as String] = (item[kSecAttrSynchronizable as String] as? Bool) ?? false
                if dataProtection, let accessible = item[kSecAttrAccessible as String] { add[kSecAttrAccessible as String] = accessible }
                if let label = item[kSecAttrLabel as String] as? String {
                    add[kSecAttrLabel as String] = label.replacingOccurrences(of: oldName, with: "Super Notes")
                }
                add[kSecValueData as String] = data
                guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { continue }
                SecItemDelete(query(old, account) as CFDictionary)
            }
        }
    }
}
