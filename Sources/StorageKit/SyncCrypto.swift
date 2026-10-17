import Foundation
import CryptoKit
import Security
import JotterCore

/// AES-256-GCM sealing for files in the sync folder: `JOT1` magic + nonce + ciphertext + tag.
public enum SyncCrypto {
    private static let magic = Data("JOT1".utf8)
    private static let context = Data("jotter.sync.v1".utf8)

    public static func seal(_ plain: Data, key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(plain, using: key, authenticating: context).combined else {
            throw StorageError(message: "Encryption failed.")
        }
        return magic + combined
    }

    public static func open(_ sealed: Data, key: SymmetricKey) throws -> Data {
        guard sealed.starts(with: magic) else { throw StorageError(message: "Not a Jotter sync file.") }
        let box = try AES.GCM.SealedBox(combined: sealed.dropFirst(magic.count))
        return try AES.GCM.open(box, using: key, authenticating: context)
    }
}

/// Where the sync key lives. Tests use an in-memory key.
@MainActor
protocol SyncKeyStoring: AnyObject {
    func load() -> SymmetricKey?
    func save(_ key: SymmetricKey) throws
    /// True when the key travels to the user's other Macs through iCloud Keychain.
    var isShared: Bool { get }
}

/// The 256-bit sync key as a synchronizable Keychain item (iCloud Keychain). Builds without the data-protection
/// keychain entitlement fall back to a local item; the key can then be moved with `exportKey`/`importKey`.
@MainActor
final class KeychainSyncKey: SyncKeyStoring {
    private let service = JotterPaths.bundleID + ".sync"
    private let account = "notes-key"
    private(set) var isShared = false

    private func baseQuery(dataProtection: Bool) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        if dataProtection { q[kSecUseDataProtectionKeychain as String] = true }
        return q
    }

    func load() -> SymmetricKey? {
        for dataProtection in [true, false] {
            var q = baseQuery(dataProtection: dataProtection)
            q[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
            q[kSecReturnData as String] = true
            q[kSecReturnAttributes as String] = true
            var out: CFTypeRef?
            if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let item = out as? [String: Any],
               let data = item[kSecValueData as String] as? Data, data.count == 32 {
                isShared = (item[kSecAttrSynchronizable as String] as? Bool) ?? false
                return SymmetricKey(data: data)
            }
        }
        return nil
    }

    func save(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }
        for dataProtection in [true, false] {
            var del = baseQuery(dataProtection: dataProtection)
            del[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
            SecItemDelete(del as CFDictionary)
        }
        var add = baseQuery(dataProtection: true)
        add[kSecAttrSynchronizable as String] = true
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecAttrLabel as String] = "Jotter sync key"
        add[kSecValueData as String] = data
        var status = SecItemAdd(add as CFDictionary, nil)
        isShared = status == errSecSuccess
        if status == errSecMissingEntitlement || status == errSecNotAvailable {
            var local = baseQuery(dataProtection: false)
            local[kSecAttrLabel as String] = "Jotter sync key"
            local[kSecValueData as String] = data
            status = SecItemAdd(local as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw StorageError(message: "Couldn't store the sync key in the Keychain (\(status)).")
        }
    }
}
