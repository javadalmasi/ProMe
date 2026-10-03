import CoreData
import CryptoKit
import Foundation
import Observation

#if canImport(UIKit)
import UIKit
#endif

/// Orchestrates encrypted snapshot sync over any S3-compatible bucket.
///
/// - `createVault` is used on the first device: it generates the master
///   key and uploads a password-wrapped copy.
/// - `joinVault` is used on additional devices: it downloads the wrapped
///   key and unwraps it with the same password.
/// - `push` uploads a signed+encrypted snapshot; `pull` downloads and
///   merges every other device's latest snapshot after signature and
///   authentication checks pass.
@MainActor
@Observable
public final class SyncService {
    public enum Phase: Equatable {
        case idle
        case working
        case done(String)
        case failed(String)
    }

    private let controller: PersistenceController
    private let keyStore: any SyncPrivateKeyStore
    private let defaults: UserDefaults

    public private(set) var phase: Phase = .idle

    public init(controller: PersistenceController, keyStore: (any SyncPrivateKeyStore)? = nil, defaults: UserDefaults = .standard) {
        self.controller = controller
        self.keyStore = keyStore ?? KeychainStore()
        self.defaults = defaults
        _ = devicePrivateKey() // ensure a device identity exists
    }

    // MARK: - Configuration

    static let configKey = "prome.sync.config"

    public var config: S3Config? {
        get {
            guard let data = defaults.data(forKey: Self.configKey) else { return nil }
            return try? JSONDecoder().decode(S3Config.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.configKey)
            } else {
                defaults.removeObject(forKey: Self.configKey)
            }
        }
    }

    public var isConfigured: Bool {
        config != nil && masterKey() != nil
    }

    /// Stores endpoint settings and the secret key (keychain only).
    public func configure(_ config: S3Config, secretKey: String) throws {
        let store = KeychainStore(service: "app.prome.sync", account: "s3-secret-key")
        try store.save(privateKeyRaw: Data(secretKey.utf8))
        self.config = config
    }

    public func secretKey() -> String? {
        let store = KeychainStore(service: "app.prome.sync", account: "s3-secret-key")
        guard let data = store.loadPrivateKeyRaw() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func disconnect() {
        config = nil
        KeychainStore(service: "app.prome.sync", account: "s3-secret-key").deletePrivateKey()
        KeychainStore(service: "app.prome.sync", account: "master-key").deletePrivateKey()
    }

    // MARK: - Keys

    static let masterKeyAccount = "master-key"

    public func devicePrivateKey() -> Curve25519.Signing.PrivateKey {
        if let raw = keyStore.loadPrivateKeyRaw(),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
            return key
        }
        let key = SyncCrypto.newDevicePrivateKey()
        try? keyStore.save(privateKeyRaw: key.rawRepresentation)
        return key
    }

    public func deviceIdentity() -> DeviceIdentity {
        DeviceIdentity(
            id: defaults.string(forKey: "prome.sync.deviceID").flatMap(UUID.init) ?? {
                let fresh = UUID()
                defaults.set(fresh.uuidString, forKey: "prome.sync.deviceID")
                return fresh
            }(),
            name: DeviceIdentityName.current,
            publicKey: devicePrivateKey().publicKey.rawRepresentation
        )
    }

    func masterKey() -> Data? {
        KeychainStore(service: "app.prome.sync", account: Self.masterKeyAccount).loadPrivateKeyRaw()
    }

    func storeMasterKey(_ key: Data) throws {
        try KeychainStore(service: "app.prome.sync", account: Self.masterKeyAccount).save(privateKeyRaw: key)
    }

    // MARK: - Vault bootstrap

    static let keywrapObject = "vault/keywrap.json"

    /// First device: generate a master key and upload it password-wrapped.
    public func createVault(password: String) async throws {
        guard let config, let secretKey = secretKey() else { throw SyncError.notConfigured }
        let masterKey = SyncCrypto.newMasterKey()
        let wrapped = try SyncCrypto.wrapMasterKey(masterKey, password: password)
        let client = S3Client(config: config, secretKey: secretKey)
        let payload = try JSONEncoder().encode(wrapped)
        try await client.put(Self.keywrapObject, data: payload, contentType: "application/json")
        try storeMasterKey(masterKey)
    }

    /// Additional device: fetch the wrapped key and unlock with password.
    public func joinVault(password: String) async throws {
        guard let config, let secretKey = secretKey() else { throw SyncError.notConfigured }
        let client = S3Client(config: config, secretKey: secretKey)
        let payload: Data
        do {
            payload = try await client.get(Self.keywrapObject)
        } catch SyncError.http(let status) where status == 404 {
            throw SyncError.notConfigured
        }
        let wrapped = try JSONDecoder().decode(SyncCrypto.WrappedKey.self, from: payload)
        let masterKey: Data
        do {
            masterKey = try SyncCrypto.unwrapMasterKey(wrapped, password: password)
        } catch {
            throw SyncError.passwordRejected
        }
        try storeMasterKey(masterKey)
    }

    /// Re-stores the master key locally without network access; used by
    /// manual key entry (e.g. restoring a device from its own backup).
    public func importMasterKey(_ key: Data) throws {
        guard key.count == SyncCrypto.masterKeyLength else { throw SyncError.decryptionFailed }
        try storeMasterKey(key)
    }

    // MARK: - Blob format

    /// magic(9) + version(1) + headerLen(4 LE) + headerJSON + ciphertext + signature(64)
    struct BlobHeader: Codable {
        var deviceID: UUID
        var deviceName: String
        var publicKey: Data
        var generatedAt: Date
        var schemaVersion: Int
    }

    static let blobMagic = Data("PROMESYNC".utf8)
    static let blobVersion: UInt8 = 1

    /// Seals and signs a snapshot. Static and pure so the security tests
    /// can exercise it without a server.
    public static func encodeBlob(_ snapshot: SyncSnapshot, signingKey: Curve25519.Signing.PrivateKey, masterKey: Data) throws -> Data {
        let header = BlobHeader(
            deviceID: snapshot.device.id,
            deviceName: snapshot.device.name,
            publicKey: signingKey.publicKey.rawRepresentation,
            generatedAt: snapshot.generatedAt,
            schemaVersion: snapshot.schemaVersion
        )
        let headerData = try JSONEncoder().encode(header)
        let payloadData = try JSONEncoder().encode(snapshot)

        let additional = additionalData(header: headerData)
        let ciphertext: Data
        do {
            ciphertext = try SyncCrypto.seal(payloadData, masterKey: masterKey, additionalData: additional)
        } catch {
            throw SyncError.decryptionFailed
        }

        var blob = Data()
        blob.append(blobMagic)
        blob.append(blobVersion)
        appendUInt32(UInt32(headerData.count), to: &blob)
        blob.append(headerData)
        blob.append(ciphertext)
        let signed = Data(blob)
        let signature = try SyncCrypto.sign(signed, privateKey: signingKey)
        blob.append(signature)
        return blob
    }

    /// Verifies the signature, then decrypts. `expectedPublicKey` comes
    /// from the device manifest and must match the blob header.
    public static func decodeBlob(_ blob: Data, masterKey: Data, expectedPublicKey: Data?) throws -> SyncSnapshot {
        let signatureLength = 64
        guard blob.count > blobMagic.count + 1 + 4 + signatureLength,
              blob.prefix(blobMagic.count) == blobMagic,
              blob[blobMagic.count] == blobVersion else {
            throw SyncError.malformedBlob
        }
        let signatureStart = blob.count - signatureLength
        let signed = blob.prefix(signatureStart)
        let signature = blob.suffix(signatureLength)

        let headerLengthStart = blobMagic.count + 1
        let headerLengthBytes = blob[headerLengthStart ..< headerLengthStart + 4]
        var headerLength: UInt32 = 0
        for (index, byte) in headerLengthBytes.enumerated() {
            headerLength |= UInt32(byte) << (8 * UInt32(index))
        }
        let headerLengthInt = Int(headerLength)
        let headerStart = headerLengthStart + 4
        guard headerLengthInt > 0, signatureStart >= headerStart + headerLengthInt else {
            throw SyncError.malformedBlob
        }
        let headerData = blob[headerStart ..< headerStart + headerLengthInt]
        let ciphertext = blob[(headerStart + headerLengthInt) ..< signatureStart]

        // Signature must verify before anything else is trusted.
        let header: BlobHeader
        do {
            header = try JSONDecoder().decode(BlobHeader.self, from: headerData)
        } catch {
            throw SyncError.malformedBlob
        }
        if let expectedPublicKey, expectedPublicKey != header.publicKey {
            throw SyncError.signatureInvalid
        }
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: header.publicKey)
        guard SyncCrypto.verify(Data(signed), signature: Data(signature), publicKey: publicKey) else {
            throw SyncError.signatureInvalid
        }

        let payloadData: Data
        do {
            payloadData = try SyncCrypto.open(Data(ciphertext), masterKey: masterKey, additionalData: additionalData(header: Data(headerData)))
        } catch {
            throw SyncError.decryptionFailed
        }
        return try JSONDecoder().decode(SyncSnapshot.self, from: payloadData)
    }

    static func additionalData(header: Data) -> Data {
        // Binds ciphertext to the exact header bytes.
        blobMagic + Data([blobVersion]) + header
    }

    static func appendUInt32(_ value: UInt32, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    // MARK: - Sync operations

    static func manifestPath(for deviceID: UUID) -> String {
        "manifests/\(deviceID.uuidString).json"
    }

    struct Manifest: Codable {
        var device: DeviceIdentity
        var schemaVersion: Int
        var lastSnapshot: String
        var generatedAt: Date
    }

    public func push() async throws {
        guard let config, let secretKey = secretKey(), let masterKey = masterKey() else {
            throw SyncError.notConfigured
        }
        phase = .working
        defer { phase = .idle }
        do {
            let device = deviceIdentity()
            let context = controller.container.newBackgroundContext()
            let snapshot = try await context.perform {
                try SnapshotEngine.export(context: context, device: device)
            }
            let blob = try Self.encodeBlob(snapshot, signingKey: devicePrivateKey(), masterKey: masterKey)

            let client = S3Client(config: config, secretKey: secretKey)
            let stamp = String(Int(snapshot.generatedAt.timeIntervalSince1970 * 1000))
            let objectKey = "snapshots/\(device.id.uuidString)/\(stamp).promeball"
            try await client.put(objectKey, data: blob, contentType: "application/octet-stream")
            let manifest = Manifest(
                device: device,
                schemaVersion: snapshot.schemaVersion,
                lastSnapshot: objectKey,
                generatedAt: snapshot.generatedAt
            )
            try await client.put(
                Self.manifestPath(for: device.id),
                data: try JSONEncoder().encode(manifest),
                contentType: "application/json"
            )
            phase = .done(String(localized: "Snapshot uploaded."))
        } catch {
            phase = .failed(error.localizedDescription)
            throw error
        }
    }

    public func pull() async throws {
        guard let config, let secretKey = secretKey(), let masterKey = masterKey() else {
            throw SyncError.notConfigured
        }
        phase = .working
        defer { phase = .idle }
        do {
            let client = S3Client(config: config, secretKey: secretKey)
            let ownID = deviceIdentity().id
            let listing = try await client.list(prefix: "manifests/")
            var totalImported = 0
            var totalUpdated = 0
            var devices = 0

            for summary in listing where summary.key.hasSuffix(".json") {
                let manifestData = try await client.get(summary.key)
                guard let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData) else { continue }
                guard manifest.device.id != ownID else { continue }

                let blob = try await client.get(manifest.lastSnapshot)
                let snapshot = try Self.decodeBlob(blob, masterKey: masterKey, expectedPublicKey: manifest.device.publicKey)
                guard snapshot.schemaVersion <= SyncSnapshot.currentSchemaVersion else { continue }

                let context = controller.container.newBackgroundContext()
                let stats: SnapshotImportStats = try await context.perform {
                    let result = try SnapshotEngine.importSnapshot(snapshot, into: context)
                    if context.hasChanges {
                        try context.save()
                    }
                    return result
                }
                totalImported += stats.imported
                totalUpdated += stats.updated
                devices += 1
            }
            phase = .done(String(localized: "Merged \(totalImported) new and \(totalUpdated) changed records from \(devices) device(s)."))
        } catch {
            phase = .failed(error.localizedDescription)
            throw error
        }
    }

    public func syncNow() async throws {
        try await pull()
        try await push()
    }
}

/// Human-readable device name across platforms.
enum DeviceIdentityName {
    static var current: String {
        #if os(macOS)
        Host.current().localizedName ?? "Mac"
        #elseif canImport(UIKit)
        UIDevice.current.name
        #else
        "ProMe Device"
        #endif
    }
}
