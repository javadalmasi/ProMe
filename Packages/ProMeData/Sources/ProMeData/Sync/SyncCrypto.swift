import CommonCrypto
import CryptoKit
import Foundation

/// Cryptographic primitives for encrypted multi-device sync.
///
/// Trust model:
/// - A random 32-byte master key encrypts every snapshot (AES-GCM).
/// - The master key is wrapped with a password-derived key (PBKDF2-
///   HMAC-SHA256, 600k iterations) before it is stored in the S3 bucket,
///   so bucket access alone reveals nothing.
/// - Each device holds an Ed25519 signing keypair; snapshots are signed
///   and every receiving device verifies the signature against the
///   publisher's public key from the manifest, so tampered or spoofed
///   snapshots are rejected.
public enum SyncCrypto {
    public static let pbkdf2Iterations: UInt32 = 600_000
    public static let saltLength = 16
    public static let masterKeyLength = 32

    // MARK: - Password key derivation (PBKDF2-HMAC-SHA256)

    public static func deriveKey(password: String, salt: Data, iterations: UInt32 = pbkdf2Iterations) -> SymmetricKey {
        // CCKeyDerivationPBKDF wants a C string; utf8CString carries the
        // null terminator, which is excluded from the length.
        let passwordBytes = Array(password.utf8CString)
        var derived = Data(repeating: 0, count: masterKeyLength)
        let status = derived.withUnsafeMutableBytes { derivedBuffer in
            salt.withUnsafeBytes { saltBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes,
                    passwordBytes.count - 1,
                    saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    derivedBuffer.bindMemory(to: UInt8.self).baseAddress,
                    masterKeyLength
                )
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 derivation failed")
        return SymmetricKey(data: derived)
    }

    // MARK: - Master key wrapping

    public struct WrappedKey: Codable, Equatable {
        public var salt: Data
        public var iterations: UInt32
        /// AES-GCM combined (nonce + ciphertext + tag) envelope.
        public var sealed: Data

        public init(salt: Data, iterations: UInt32, sealed: Data) {
            self.salt = salt
            self.iterations = iterations
            self.sealed = sealed
        }
    }

    /// Wraps a raw master key with a password. Fresh random salt every call.
    public static func wrapMasterKey(_ masterKey: Data, password: String) throws -> WrappedKey {
        let salt = randomData(count: saltLength)
        let key = deriveKey(password: password, salt: salt)
        let sealed = try AES.GCM.seal(masterKey, using: key).combined!
        return WrappedKey(salt: salt, iterations: pbkdf2Iterations, sealed: sealed)
    }

    /// Unwraps the master key. Throws when the password is wrong (AES-GCM
    /// authentication failure).
    public static func unwrapMasterKey(_ wrapped: WrappedKey, password: String) throws -> Data {
        let key = deriveKey(password: password, salt: wrapped.salt, iterations: wrapped.iterations)
        let box = try AES.GCM.SealedBox(combined: wrapped.sealed)
        return try AES.GCM.open(box, using: key)
    }

    // MARK: - Payload encryption

    /// Encrypts a payload with the master key. The additional data binds
    /// the ciphertext to a device and schema version, preventing cut-and-
    /// paste attacks across devices or format versions.
    public static func seal(_ plaintext: Data, masterKey: Data, additionalData: Data) throws -> Data {
        let key = SymmetricKey(data: masterKey)
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: additionalData)
        return box.combined!
    }

    /// Decrypts a payload. Throws on any tampering with ciphertext, tag,
    /// or additional data.
    public static func open(_ sealed: Data, masterKey: Data, additionalData: Data) throws -> Data {
        let key = SymmetricKey(data: masterKey)
        let box = try AES.GCM.SealedBox(combined: sealed)
        return try AES.GCM.open(box, using: key, authenticating: additionalData)
    }

    // MARK: - Device signatures (Ed25519)

    public static func sign(_ data: Data, privateKey: Curve25519.Signing.PrivateKey) throws -> Data {
        try privateKey.signature(for: data)
    }

    /// Constant-time verification of a snapshot signature.
    public static func verify(_ data: Data, signature: Data, publicKey: Curve25519.Signing.PublicKey) -> Bool {
        publicKey.isValidSignature(signature, for: data)
    }

    public static func newDevicePrivateKey() -> Curve25519.Signing.PrivateKey {
        Curve25519.Signing.PrivateKey()
    }

    public static func newMasterKey() -> Data {
        randomData(count: masterKeyLength)
    }

    public static func randomData(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "Secure random generator unavailable")
        return Data(bytes)
    }
}
