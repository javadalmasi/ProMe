import CryptoKit
import Foundation

/// Where a device's Ed25519 private key lives. The production backend is
/// the keychain; tests use an in-memory backend.
public protocol SyncPrivateKeyStore: Sendable {
    func save(privateKeyRaw: Data) throws
    func loadPrivateKeyRaw() -> Data?
    func deletePrivateKey()
}

/// Generic-password keychain backend. The signing seed is stored as an
/// opaque secret (kSecClassGenericPassword) available offline on all
/// Apple platforms, including while the device is locked enough for
/// background sync.
public struct KeychainStore: SyncPrivateKeyStore {
    let service: String
    let account: String

    public init(service: String = "app.prome.sync", account: String = "device-signing-key") {
        self.service = service
        self.account = account
    }

    public func save(privateKeyRaw: Data) throws {
        deletePrivateKey()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: privateKeyRaw,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SyncError.keychainFailure(status)
        }
    }

    public func loadPrivateKeyRaw() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    public func deletePrivateKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// In-memory backend for unit tests.
public final class InMemoryKeyStore: SyncPrivateKeyStore, @unchecked Sendable {
    private var storage: Data?
    private let lock = NSLock()

    public init() {}

    public func save(privateKeyRaw: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        storage = privateKeyRaw
    }

    public func loadPrivateKeyRaw() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    public func deletePrivateKey() {
        lock.lock()
        defer { lock.unlock() }
        storage = nil
    }
}

/// A device participating in the sync vault.
public struct DeviceIdentity: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// Raw 32-byte Ed25519 public key.
    public var publicKey: Data

    public init(id: UUID = UUID(), name: String, publicKey: Data) {
        self.id = id
        self.name = name
        self.publicKey = publicKey
    }
}
