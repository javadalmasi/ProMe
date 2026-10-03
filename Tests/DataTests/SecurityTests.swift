import CoreData
import CryptoKit
import Foundation
import ProMeData
import ProMeDomain
import Testing

/// Security unit tests for the encrypted S3 sync: key derivation, master
/// key wrapping, authenticated encryption, snapshot signing, blob tamper
/// detection, SigV4 signing and snapshot merge semantics.
@Suite("Sync security")
@MainActor
struct SecurityTests {

    // MARK: - PBKDF2 / master key wrapping

    @Test("PBKDF2 derivation is deterministic and salt-sensitive")
    func pbkdf2Deterministic() {
        let salt = Data(repeating: 7, count: 16)
        let a = SyncCrypto.deriveKey(password: "correct horse", salt: salt, iterations: 10_000)
        let b = SyncCrypto.deriveKey(password: "correct horse", salt: salt, iterations: 10_000)
        let c = SyncCrypto.deriveKey(password: "correct horse", salt: Data(repeating: 8, count: 16), iterations: 10_000)
        let d = SyncCrypto.deriveKey(password: "Correct horse", salt: salt, iterations: 10_000)
        #expect(a.withUnsafeBytes { Data($0) } == b.withUnsafeBytes { Data($0) })
        #expect(a.withUnsafeBytes { Data($0) } != c.withUnsafeBytes { Data($0) })
        #expect(a.withUnsafeBytes { Data($0) } != d.withUnsafeBytes { Data($0) })
    }

    @Test("PBKDF2 matches the published HMAC-SHA256 vector")
    func pbkdf2Vector() {
        // PBKDF2-HMAC-SHA256("password", 00112233..., 1000, 32B), computed
        // independently with Python's hashlib.
        let salt = Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        let key = SyncCrypto.deriveKey(password: "password", salt: salt, iterations: 1_000)
        let hex = key.withUnsafeBytes { Data($0).map { String(format: "%02x", $0) }.joined() }
        #expect(hex == "6ed2147b9b670624275a8ab15759524ca062d8992aadae6a083b4bc148d12027")
    }

    @Test("Master key wrap/unwrap roundtrip and wrong-password rejection")
    func masterKeyWrap() throws {
        let masterKey = SyncCrypto.newMasterKey()
        #expect(masterKey.count == 32)

        let wrapped = try SyncCrypto.wrapMasterKey(masterKey, password: "فارسی-پسورد-۱۲۳")
        let unwrapped = try SyncCrypto.unwrapMasterKey(wrapped, password: "فارسی-پسورد-۱۲۳")
        #expect(unwrapped == masterKey)

        #expect(throws: Error.self) {
            try SyncCrypto.unwrapMasterKey(wrapped, password: "wrong password")
        }
    }

    @Test("Master keys and salts are unique per wrap")
    func wrapRandomness() throws {
        let masterKey = SyncCrypto.newMasterKey()
        let first = try SyncCrypto.wrapMasterKey(masterKey, password: "same")
        let second = try SyncCrypto.wrapMasterKey(masterKey, password: "same")
        #expect(first.salt != second.salt)
        #expect(first.sealed != second.sealed)
    }

    // MARK: - Authenticated encryption

    @Test("AES-GCM seal/open roundtrip")
    func sealOpen() throws {
        let masterKey = SyncCrypto.newMasterKey()
        let aad = Data("device-1|schema=1".utf8)
        let plaintext = Data("تراکنش‌ها و یادداشت‌های شخصی 🤝".utf8)
        let sealed = try SyncCrypto.seal(plaintext, masterKey: masterKey, additionalData: aad)
        #expect(sealed != plaintext)
        let opened = try SyncCrypto.open(sealed, masterKey: masterKey, additionalData: aad)
        #expect(opened == plaintext)
    }

    @Test("Tampered ciphertext is rejected")
    func tamperDetection() throws {
        let masterKey = SyncCrypto.newMasterKey()
        let aad = Data("aad".utf8)
        var sealed = try SyncCrypto.seal(Data("payload".utf8), masterKey: masterKey, additionalData: aad)
        sealed[sealed.count / 2] ^= 0xFF
        #expect(throws: Error.self) {
            try SyncCrypto.open(sealed, masterKey: masterKey, additionalData: aad)
        }
    }

    @Test("Swapped additional data is rejected (cut-and-paste defense)")
    func aadBinding() throws {
        let masterKey = SyncCrypto.newMasterKey()
        let sealed = try SyncCrypto.seal(Data("payload".utf8), masterKey: masterKey, additionalData: Data("device-A".utf8))
        #expect(throws: Error.self) {
            try SyncCrypto.open(sealed, masterKey: masterKey, additionalData: Data("device-B".utf8))
        }
    }

    @Test("A different master key cannot decrypt")
    func wrongKeyRejected() throws {
        let sealed = try SyncCrypto.seal(Data("payload".utf8), masterKey: SyncCrypto.newMasterKey(), additionalData: Data())
        #expect(throws: Error.self) {
            try SyncCrypto.open(sealed, masterKey: SyncCrypto.newMasterKey(), additionalData: Data())
        }
    }

    // MARK: - Ed25519 device signatures

    @Test("Snapshot signatures verify and reject tampering")
    func signatureRoundtrip() throws {
        let deviceKey = SyncCrypto.newDevicePrivateKey()
        let payload = Data("snapshot-bytes".utf8)
        let signature = try SyncCrypto.sign(payload, privateKey: deviceKey)

        #expect(SyncCrypto.verify(payload, signature: signature, publicKey: deviceKey.publicKey))

        var tampered = payload
        tampered[3] ^= 0x01
        #expect(!SyncCrypto.verify(tampered, signature: signature, publicKey: deviceKey.publicKey))

        let impostor = SyncCrypto.newDevicePrivateKey()
        #expect(!SyncCrypto.verify(payload, signature: signature, publicKey: impostor.publicKey))
    }

    // MARK: - Sync blob

    private func sampleSnapshot(deviceID: UUID = UUID()) -> SyncSnapshot {
        SyncSnapshot(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            device: DeviceIdentity(id: deviceID, name: "Test Mac", publicKey: Data(repeating: 1, count: 32)),
            entities: [],
            deletions: []
        )
    }

    @Test("Blob encode/decode roundtrip")
    func blobRoundtrip() throws {
        let deviceKey = SyncCrypto.newDevicePrivateKey()
        let masterKey = SyncCrypto.newMasterKey()
        let snapshot = sampleSnapshot()

        let blob = try SyncService.encodeBlob(snapshot, signingKey: deviceKey, masterKey: masterKey)
        let decoded = try SyncService.decodeBlob(blob, masterKey: masterKey, expectedPublicKey: deviceKey.publicKey.rawRepresentation)
        #expect(decoded.device.id == snapshot.device.id)
        #expect(decoded.generatedAt == snapshot.generatedAt)
    }

    @Test("Blob with flipped byte fails signature verification")
    func blobTamperRejected() throws {
        let deviceKey = SyncCrypto.newDevicePrivateKey()
        let masterKey = SyncCrypto.newMasterKey()
        var blob = try SyncService.encodeBlob(sampleSnapshot(), signingKey: deviceKey, masterKey: masterKey)
        blob[blob.count - 70] ^= 0xFF // inside the ciphertext region
        #expect(throws: SyncError.signatureInvalid) {
            try SyncService.decodeBlob(blob, masterKey: masterKey, expectedPublicKey: deviceKey.publicKey.rawRepresentation)
        }
    }

    @Test("Blob with the wrong master key fails authentication, not panic")
    func blobWrongKeyRejected() throws {
        let deviceKey = SyncCrypto.newDevicePrivateKey()
        let blob = try SyncService.encodeBlob(sampleSnapshot(), signingKey: deviceKey, masterKey: SyncCrypto.newMasterKey())
        #expect(throws: SyncError.decryptionFailed) {
            try SyncService.decodeBlob(blob, masterKey: SyncCrypto.newMasterKey(), expectedPublicKey: nil)
        }
    }

    @Test("Blob public key mismatch is rejected (spoofed publisher)")
    func blobKeyMismatch() throws {
        let deviceKey = SyncCrypto.newDevicePrivateKey()
        let masterKey = SyncCrypto.newMasterKey()
        let blob = try SyncService.encodeBlob(sampleSnapshot(), signingKey: deviceKey, masterKey: masterKey)
        #expect(throws: SyncError.signatureInvalid) {
            try SyncService.decodeBlob(blob, masterKey: masterKey, expectedPublicKey: SyncCrypto.newDevicePrivateKey().publicKey.rawRepresentation)
        }
    }

    @Test("Garbage blob is malformed, not crashing")
    func blobGarbage() {
        #expect(throws: SyncError.malformedBlob) {
            try SyncService.decodeBlob(Data("not a blob at all".utf8), masterKey: SyncCrypto.newMasterKey(), expectedPublicKey: nil)
        }
        #expect(throws: SyncError.malformedBlob) {
            try SyncService.decodeBlob(Data(), masterKey: SyncCrypto.newMasterKey(), expectedPublicKey: nil)
        }
    }

    // MARK: - Keychain

    @Test("Keychain store roundtrip")
    func keychainRoundtrip() throws {
        let store = KeychainStore(service: "app.prome.tests", account: "test-\(UUID().uuidString)")
        let raw = SyncCrypto.newMasterKey()
        defer { store.deletePrivateKey() }

        try store.save(privateKeyRaw: raw)
        let loaded = store.loadPrivateKeyRaw()
        #expect(loaded == raw)

        store.deletePrivateKey()
        #expect(store.loadPrivateKeyRaw() == nil)
    }

    @Test("Keychain overwrite replaces the previous secret")
    func keychainOverwrite() throws {
        let store = KeychainStore(service: "app.prome.tests", account: "overwrite-\(UUID().uuidString)")
        defer { store.deletePrivateKey() }
        try store.save(privateKeyRaw: Data(repeating: 1, count: 32))
        try store.save(privateKeyRaw: Data(repeating: 2, count: 32))
        #expect(store.loadPrivateKeyRaw() == Data(repeating: 2, count: 32))
    }

    // MARK: - SigV4

    @Test("SigV4 signature matches the AWS documented vector")
    func sigV4Vector() {
        // The canonical GET / example from the AWS SigV4 documentation:
        // host example.amazonaws.com, 20150830T123600Z, us-east-1/service,
        // empty payload.
        let authorization = S3Client.authorizationHeader(
            method: "GET",
            canonicalURI: "/",
            canonicalQuery: "",
            headers: ["host": "example.amazonaws.com", "x-amz-date": "20150830T123600Z"],
            signedHeaderNames: ["host", "x-amz-date"],
            payloadHash: S3Client.sha256Hex(Data()),
            accessKey: "AKIDEXAMPLE",
            secretKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
            amzDate: "20150830T123600Z",
            dateStamp: "20150830",
            region: "us-east-1",
            service: "service"
        )
        #expect(authorization.contains("Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request"))
        #expect(authorization.contains("SignedHeaders=host;x-amz-date"))
        #expect(authorization.contains("Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31"))
    }

    @Test("Canonical query is sorted and percent-encoded")
    func canonicalQuery() {
        let query = S3Client.canonicalQuery(from: [
            "prefix": "prome/snapshots/a b",
            "list-type": "2",
            "max-keys": "1000",
        ])
        #expect(query == "list-type=2&max-keys=1000&prefix=prome%2Fsnapshots%2Fa%20b")
    }

    @Test("Path encoding keeps separators and escapes segments")
    func pathEncoding() {
        #expect(S3Client.encodePath("/bucket/prome/a b/c+d.snap") == "/bucket/prome/a%20b/c%2Bd.snap")
        #expect(S3Client.urlEncode("a/b") == "a%2Fb")
        #expect(S3Client.urlEncode("a/b", isPath: true) == "a/b")
    }

    @Test("Empty payload hash is the SHA-256 of nothing")
    func emptyPayloadHash() {
        #expect(S3Client.sha256Hex(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    // MARK: - Snapshot merge (LWW + tombstones)

    @Test("Snapshot export/import roundtrips across two stores")
    func snapshotRoundtripAcrossStores() throws {
        let source = try PersistenceController(inMemory: true)
        let target = try PersistenceController(inMemory: true)
        let sourceContext = source.container.viewContext
        let targetContext = target.container.viewContext

        let scope = FinancialScopeMO(context: sourceContext)
        scope.id = UUID(); scope.name = "شخصی"; scope.kind = .personal; scope.isActive = true; scope.createdAt = .now

        let account = MoneyAccountMO(context: sourceContext)
        account.id = UUID(); account.name = "بانک ملت"; account.type = .current
        account.currencyCode = "IRR"; account.openingBalanceMinor = 1_000_000
        account.openedAt = .now; account.status = .active; account.position = 0
        account.createdAt = .now; account.updatedAt = .now; account.scope = scope

        let task = TaskItemMO(context: sourceContext)
        task.id = UUID(); task.title = "قبض برق را پرداخت کن"; task.priority = .high
        task.status = .pending; task.repeatRule = .none; task.dateKey = 14040710
        task.createdAt = .now; task.updatedAt = .now

        let note = NoteMO(context: sourceContext)
        note.id = UUID(); note.bodyText = "یادداشت شخصی"; note.isPinned = true
        note.dateKey = 14040710; note.createdAt = .now; note.updatedAt = .now

        let device = DeviceIdentity(id: UUID(), name: "A", publicKey: Data(repeating: 3, count: 32))
        let snapshot = try SnapshotEngine.export(context: sourceContext, device: device)
        let stats = try SnapshotEngine.importSnapshot(snapshot, into: targetContext)
        try targetContext.save()

        #expect(stats.imported >= 4)
        let accountRequest = MoneyAccountMO.fetchRequest()
        let importedAccount = try #require(try targetContext.fetch(accountRequest).first)
        #expect(importedAccount.name == "بانک ملت")
        #expect(importedAccount.scope?.name == "شخصی")
        let taskRequest = TaskItemMO.fetchRequest()
        let importedTask = try #require(try targetContext.fetch(taskRequest).first)
        #expect(importedTask.title == "قبض برق را پرداخت کن")
        #expect(importedTask.priority == .high)

        // Second import of the same snapshot must not duplicate anything.
        let second = try SnapshotEngine.importSnapshot(snapshot, into: targetContext)
        #expect(second.imported == 0)
        #expect(try targetContext.fetch(accountRequest).count == 1)
    }

    @Test("Last-writer-wins: newer remote updates, older remote loses")
    func lastWriterWins() throws {
        let source = try PersistenceController(inMemory: true)
        let target = try PersistenceController(inMemory: true)
        let sourceContext = source.container.viewContext
        let targetContext = target.container.viewContext

        func makeNote(in context: NSManagedObjectContext, body: String, updated: Date) -> NoteMO {
            let note = NoteMO(context: context)
            note.id = UUID()
            note.bodyText = body
            note.dateKey = 1
            note.createdAt = .distantPast
            note.updatedAt = updated
            return note
        }

        // Same id in both stores, local is older.
        let sharedID = UUID()
        let remoteNote = makeNote(in: sourceContext, body: "نسخه جدید", updated: Date(timeIntervalSince1970: 2_000))
        remoteNote.id = sharedID
        let localNote = makeNote(in: targetContext, body: "نسخه قدیمی", updated: Date(timeIntervalSince1970: 1_000))
        localNote.id = sharedID

        // And a second note where local is newer.
        let newerID = UUID()
        let remoteOld = makeNote(in: sourceContext, body: "ریموت قدیمی", updated: Date(timeIntervalSince1970: 500))
        remoteOld.id = newerID
        let localNew = makeNote(in: targetContext, body: "لوکال جدید", updated: Date(timeIntervalSince1970: 3_000))
        localNew.id = newerID

        let device = DeviceIdentity(id: UUID(), name: "A", publicKey: Data(repeating: 4, count: 32))
        let snapshot = try SnapshotEngine.export(context: sourceContext, device: device)
        let stats = try SnapshotEngine.importSnapshot(snapshot, into: targetContext)
        try targetContext.save()

        let request = NoteMO.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "bodyText", ascending: true)]
        let notes = try targetContext.fetch(request)
        let bodies = Set(notes.map(\.bodyText))
        #expect(bodies.contains("نسخه جدید"), "newer remote must overwrite older local")
        #expect(bodies.contains("لوکال جدید"), "newer local must survive older remote")
        #expect(!bodies.contains("نسخه قدیمی"))
        #expect(!bodies.contains("ریموت قدیمی"))
        #expect(stats.updated == 1)
        _ = notes
    }

    @Test("Deletions propagate as tombstones")
    func tombstonePropagation() throws {
        let source = try PersistenceController(inMemory: true)
        let target = try PersistenceController(inMemory: true)
        let sourceContext = source.container.viewContext
        let targetContext = target.container.viewContext

        let task = TaskItemMO(context: sourceContext)
        task.id = UUID(); task.title = "حذف شود"; task.priority = .normal
        task.status = .pending; task.repeatRule = .none; task.dateKey = 1
        task.createdAt = .now; task.updatedAt = .now
        // Persist first: a task that exists on another device must be an
        // already-saved row before it is deleted (objects created and
        // deleted within one save never produce a deletion commit).
        try sourceContext.save()

        let device = DeviceIdentity(id: UUID(), name: "A", publicKey: Data(repeating: 5, count: 32))
        let firstSnapshot = try SnapshotEngine.export(context: sourceContext, device: device)
        _ = try SnapshotEngine.importSnapshot(firstSnapshot, into: targetContext)
        try targetContext.save()

        // Delete on the source through the real service path so the
        // PersistenceController tombstone hook records it.
        let services = TaskService(controller: source)
        try services.delete(task)

        let secondSnapshot = try SnapshotEngine.export(context: sourceContext, device: device)
        #expect(secondSnapshot.deletions.contains { $0.entityName == "TaskItem" })
        _ = try SnapshotEngine.importSnapshot(secondSnapshot, into: targetContext)
        try targetContext.save()

        let request = TaskItemMO.fetchRequest()
        #expect(try targetContext.fetch(request).isEmpty, "remote deletion must remove the local row")
    }
}

/// Iranian bank registry, card and Sheba validation.
@Suite("Iranian banks")
struct IranianBankTests {
    @Test("BIN lookup identifies banks")
    func binLookup() {
        #expect(IranianBank.matching(cardNumber: "6037991234567890")?.id == "bmi")
        #expect(IranianBank.matching(cardNumber: "6104331234567890")?.id == "mellat")
        #expect(IranianBank.matching(cardNumber: "5022291234567890")?.id == "pasargad")
        #expect(IranianBank.matching(cardNumber: "603769-1234-5678-90")?.id == "saderat", "non-digits are ignored")
        #expect(IranianBank.matching(cardNumber: "9999991234567890") == nil)
        #expect(IranianBank.matching(cardNumber: "6037") == nil)
    }

    @Test("Every registered bank is complete")
    func registryIntegrity() {
        #expect(IranianBank.all.count >= 25)
        for bank in IranianBank.all {
            #expect(!bank.name.isEmpty)
            #expect(!bank.monogram.isEmpty)
            #expect(bank.colorHex.hasPrefix("#") && bank.colorHex.count == 7)
        }
        let ids = IranianBank.all.map(\.id)
        #expect(Set(ids).count == ids.count, "ids must be unique")
    }

    @Test("Luhn checksum validates card numbers")
    func luhn() {
        // 6037991234567893 is Luhn-valid (check digit computed for the test).
        #expect(CardValidator.luhnValid("6037991234567893"))
        #expect(!CardValidator.luhnValid("6037991234567894"))
        // A Luhn-valid 16-digit number: the classic test card.
        #expect(CardValidator.luhnValid("4111111111111111"))
        #expect(!CardValidator.luhnValid("4111111111111112"))
        #expect(!CardValidator.luhnValid("1234"))
    }

    @Test("Sheba validation with published IBANs")
    func sheba() {
        #expect(ShebaValidator.isValid("IR820540102680020817909002"))
        #expect(ShebaValidator.isValid("ir06 2960 0000 0010 0324 2000 01"))
        #expect(!ShebaValidator.isValid("IR820540102680020817909003"))
        #expect(!ShebaValidator.isValid("GR96 0810 1010 0000 0123 4567 890"))
        #expect(!ShebaValidator.isValid("IR00"))
        #expect(ShebaValidator.bankCode(of: "IR820540102680020817909002") == "054")
        #expect(IranianBank.matching(shebaCode: "054")?.id == "parsian")
    }

    @Test("Card numbers are formatted in groups of four")
    func cardFormatting() {
        #expect(CardValidator.formattedCardNumber("6037991234567890") == "6037-9912-3456-7890")
        // Only ASCII digits survive normalization.
        #expect(CardValidator.digits(in: "6037-9912 3456 7890") == "6037991234567890")
    }
}
