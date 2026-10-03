import CoreData
import Foundation

public enum SyncError: Error, Equatable {
    case notConfigured
    case keychainFailure(OSStatus)
    case network(String)
    case http(status: Int)
    case decryptionFailed
    case signatureInvalid
    case passwordRejected
    case malformedBlob
    case modelUnavailable(String)
}

extension SyncError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured: String(localized: "Sync is not configured.")
        case .keychainFailure(let status): String(localized: "Keychain error (\(status)).")
        case .network(let detail): String(localized: "Network error: \(detail)")
        case .http(let status): String(localized: "Server returned status \(status).")
        case .decryptionFailed: String(localized: "Could not decrypt the snapshot. The password or key is wrong.")
        case .signatureInvalid: String(localized: "Snapshot signature is invalid. The data may be tampered with.")
        case .passwordRejected: String(localized: "Wrong password.")
        case .malformedBlob: String(localized: "The snapshot file is malformed.")
        case .modelUnavailable(let name): String(localized: "Unknown entity in snapshot: \(name)")
        }
    }
}

/// A dynamically typed value inside a snapshot record.
public enum SyncValue: Codable, Hashable, Sendable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case uuid(UUID)
    case data(Data)
    case null

    private enum CodingKeys: String, CodingKey { case t, v }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .t)
        switch type {
        case "s": self = .string(try container.decode(String.self, forKey: .v))
        case "i": self = .int(try container.decode(Int64.self, forKey: .v))
        case "d": self = .double(try container.decode(Double.self, forKey: .v))
        case "b": self = .bool(try container.decode(Bool.self, forKey: .v))
        case "D": self = .date(try container.decode(Date.self, forKey: .v))
        case "u": self = .uuid(try container.decode(UUID.self, forKey: .v))
        case "x": self = .data(try container.decode(Data.self, forKey: .v))
        default: self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let value):
            try container.encode("s", forKey: .t)
            try container.encode(value, forKey: .v)
        case .int(let value):
            try container.encode("i", forKey: .t)
            try container.encode(value, forKey: .v)
        case .double(let value):
            try container.encode("d", forKey: .t)
            try container.encode(value, forKey: .v)
        case .bool(let value):
            try container.encode("b", forKey: .t)
            try container.encode(value, forKey: .v)
        case .date(let value):
            try container.encode("D", forKey: .t)
            try container.encode(value, forKey: .v)
        case .uuid(let value):
            try container.encode("u", forKey: .t)
            try container.encode(value, forKey: .v)
        case .data(let value):
            try container.encode("x", forKey: .t)
            try container.encode(value, forKey: .v)
        case .null:
            try container.encode("0", forKey: .t)
        }
    }
}

/// One entity's worth of records. To-one relationships are stored under
/// "rel:<name>" pointing at the target's UUID; to-many under "relm:<name>".
public struct SyncEntityData: Codable, Sendable {
    public var entityName: String
    public var records: [[String: SyncValue]]

    public init(entityName: String, records: [[String: SyncValue]]) {
        self.entityName = entityName
        self.records = records
    }
}

public struct DeletionRecord: Codable, Hashable, Sendable {
    public var entityName: String
    public var recordID: UUID
    public var deletedAt: Date

    public init(entityName: String, recordID: UUID, deletedAt: Date) {
        self.entityName = entityName
        self.recordID = recordID
        self.deletedAt = deletedAt
    }
}

/// The full encrypted payload: every synced entity plus the deletion log.
public struct SyncSnapshot: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var generatedAt: Date
    public var device: DeviceIdentity
    public var entities: [SyncEntityData]
    public var deletions: [DeletionRecord]

    public init(schemaVersion: Int, generatedAt: Date, device: DeviceIdentity, entities: [SyncEntityData], deletions: [DeletionRecord]) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.device = device
        self.entities = entities
        self.deletions = deletions
    }
}

public struct SnapshotImportStats: Equatable, Sendable {
    public var imported = 0
    public var updated = 0
    public var skipped = 0

    public init() {}
}

/// Serializes the whole store to and from `SyncSnapshot`s, using the Core
/// Data model metadata at runtime — adding a model attribute automatically
/// extends the snapshot format without code changes.
public enum SnapshotEngine {
    /// Exported and imported in dependency order. Derived ledger entities
    /// (LedgerAccount, Journal, LedgerLine) are rebuilt by the posting
    /// engine and are deliberately not synced; attachments stay local.
    public static let syncedEntities: [String] = [
        "FinancialScope", "Business", "UserProfile", "MoneyAccount", "Category",
        "Tag", "Counterparty", "Transaction", "RecurringTransaction", "BudgetEntry",
        "Debt", "DebtPayment", "Loan", "LoanInstallment", "Insurance", "Asset",
        "AssetValuation", "Reconciliation",
        "TaskItem", "ActivityEntry", "AlertItem", "Appointment", "Note", "Place",
    ]

    /// Entities that carry `updatedAt` participate in last-writer-wins;
    /// insert-only entities keep the local row when the id already exists.
    static func hasUpdatedAt(_ entity: NSEntityDescription) -> Bool {
        entity.attributesByName["updatedAt"] != nil
    }

    // MARK: - Export

    public static func export(context: NSManagedObjectContext, device: DeviceIdentity) throws -> SyncSnapshot {
        var entities: [SyncEntityData] = []
        let model = context.persistentStoreCoordinator?.managedObjectModel
        for name in syncedEntities {
            guard let entity = model?.entitiesByName[name] else {
                throw SyncError.modelUnavailable(name)
            }
            let request = NSFetchRequest<NSManagedObject>(entityName: name)
            let objects = try context.fetch(request)
            var records: [[String: SyncValue]] = []
            for object in objects {
                records.append(exportRecord(object, entity: entity))
            }
            entities.append(SyncEntityData(entityName: name, records: records))
        }

        let deletionRequest = NSFetchRequest<DeletionLogMO>(entityName: "DeletionLog")
        let deletionObjects = try context.fetch(deletionRequest)
        let deletions = deletionObjects.map {
            DeletionRecord(entityName: $0.recordEntity, recordID: $0.recordID, deletedAt: $0.deletedAt)
        }

        return SyncSnapshot(
            schemaVersion: SyncSnapshot.currentSchemaVersion,
            generatedAt: .now,
            device: device,
            entities: entities,
            deletions: deletions
        )
    }

    static func exportRecord(_ object: NSManagedObject, entity: NSEntityDescription) -> [String: SyncValue] {
        var record: [String: SyncValue] = [:]
        for (name, attribute) in entity.attributesByName {
            let value = object.value(forKey: name)
            record[name] = syncValue(from: value, attributeType: attribute.attributeType)
        }
        for (name, relationship) in entity.relationshipsByName where !relationship.isToMany {
            if let target = object.value(forKey: name) as? NSManagedObject,
               let targetID = target.value(forKey: "id") as? UUID {
                record["rel:\(name)"] = .uuid(targetID)
            } else {
                record["rel:\(name)"] = .null
            }
        }
        for (name, relationship) in entity.relationshipsByName where relationship.isToMany {
            if let targets = object.value(forKey: name) as? Set<NSManagedObject> {
                let ids = targets.compactMap { $0.value(forKey: "id") as? UUID }.map(SyncValue.uuid)
                // Lists ride inside a JSON string to keep SyncValue flat.
                record["relm:\(name)"] = encodeList(ids)
            }
        }
        return record
    }

    static func encodeList(_ values: [SyncValue]) -> SyncValue {
        // Lists are encoded as a JSON array string to keep SyncValue flat.
        if let data = try? JSONEncoder().encode(values),
           let string = String(data: data, encoding: .utf8) {
            return .string(string)
        }
        return .null
    }

    public static func syncValue(from value: Any?, attributeType: NSAttributeType) -> SyncValue {
        guard let value else { return .null }
        switch attributeType {
        case .stringAttributeType:
            if let string = value as? String { return .string(string) }
        case .booleanAttributeType:
            if let bool = value as? Bool { return .bool(bool) }
        case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType:
            if let number = value as? NSNumber { return .int(number.int64Value) }
        case .doubleAttributeType, .floatAttributeType, .decimalAttributeType:
            if let number = value as? NSNumber { return .double(number.doubleValue) }
        case .dateAttributeType:
            if let date = value as? Date { return .date(date) }
        case .UUIDAttributeType:
            if let uuid = value as? UUID { return .uuid(uuid) }
        case .binaryDataAttributeType:
            if let data = value as? Data { return .data(data) }
        default:
            break
        }
        return .null
    }

    // MARK: - Import

    public static func importSnapshot(
        _ snapshot: SyncSnapshot, into context: NSManagedObjectContext
    ) throws -> SnapshotImportStats {
        var stats = SnapshotImportStats()
        let model = context.persistentStoreCoordinator?.managedObjectModel

        // Local deletion log, used to keep deletions authoritative.
        let localTombstones = try fetchTombstones(context)

        var pendingRelationships: [(object: NSManagedObject, name: String, targetID: UUID, destination: String)] = []
        var pendingToMany: [(object: NSManagedObject, name: String, targetIDs: [UUID], destination: String)] = []

        for entityData in snapshot.entities {
            guard syncedEntities.contains(entityData.entityName),
                  let entity = model?.entitiesByName[entityData.entityName] else { continue }
            let hasUpdatedAt = Self.hasUpdatedAt(entity)

            // Existing rows by id for this entity.
            let request = NSFetchRequest<NSManagedObject>(entityName: entityData.entityName)
            let existing = try context.fetch(request)
            var byID: [UUID: NSManagedObject] = [:]
            for object in existing {
                if let id = object.value(forKey: "id") as? UUID {
                    byID[id] = object
                }
            }

            for record in entityData.records {
                guard case .uuid(let id) = record["id"] ?? .null else { continue }

                let remoteUpdatedAt = record["updatedAt"]
                if let tombstone = localTombstones["\(entityData.entityName)/\(id.uuidString)"] {
                    // Deletion wins unless the record changed after deletion.
                    if let remoteUpdated = remoteUpdatedAt, case .date(let date) = remoteUpdated, date > tombstone {
                        // resurrect below
                    } else {
                        stats.skipped += 1
                        continue
                    }
                }

                if let local = byID[id] {
                    guard hasUpdatedAt, case .date(let remoteDate) = remoteUpdatedAt ?? .null else {
                        stats.skipped += 1
                        continue
                    }
                    let localDate = (local.value(forKey: "updatedAt") as? Date) ?? .distantPast
                    guard remoteDate > localDate else {
                        stats.skipped += 1
                        continue
                    }
                    apply(record: record, entity: entity, to: local, relationships: &pendingRelationships, toMany: &pendingToMany)
                    stats.updated += 1
                } else {
                    let object = NSEntityDescription.insertNewObject(forEntityName: entityData.entityName, into: context)
                    object.setValue(id, forKey: "id")
                    apply(record: record, entity: entity, to: object, relationships: &pendingRelationships, toMany: &pendingToMany)
                    stats.imported += 1
                }
            }
        }

        // Merge the remote deletion log: apply deletions for rows that are
        // not newer locally, and keep the log itself in sync.
        for deletion in snapshot.deletions {
            guard syncedEntities.contains(deletion.entityName) else { continue }
            let key = "\(deletion.entityName)/\(deletion.recordID.uuidString)"
            if localTombstones[key] != nil { continue }
            let request = NSFetchRequest<NSManagedObject>(entityName: deletion.entityName)
            request.predicate = NSPredicate(format: "id == %@", deletion.recordID as CVarArg)
            request.fetchLimit = 1
            if let local = try context.fetch(request).first {
                let localDate = (local.value(forKey: "updatedAt") as? Date) ?? .distantPast
                if localDate <= deletion.deletedAt {
                    context.delete(local)
                }
            }
            let logEntry = DeletionLogMO(context: context)
            logEntry.id = UUID()
            logEntry.recordEntity = deletion.entityName
            logEntry.recordID = deletion.recordID
            logEntry.deletedAt = deletion.deletedAt
        }

        // Resolve deferred relationships now that every row exists.
        for pending in pendingRelationships {
            if let target = try findByID(pending.targetID, entityName: pending.destination, in: context) {
                pending.object.setValue(target, forKey: pending.name)
            }
        }
        for pending in pendingToMany {
            for targetID in pending.targetIDs {
                if let target = try findByID(targetID, entityName: pending.destination, in: context) {
                    pending.object.mutableSetValue(forKey: pending.name).add(target)
                }
            }
        }

        return stats
    }

    static func apply(
        record: [String: SyncValue], entity: NSEntityDescription, to object: NSManagedObject,
        relationships: inout [(object: NSManagedObject, name: String, targetID: UUID, destination: String)],
        toMany: inout [(object: NSManagedObject, name: String, targetIDs: [UUID], destination: String)]
    ) {
        for (name, attribute) in entity.attributesByName {
            guard let value = record[name] else { continue }
            object.setValue(nativeValue(value, attributeType: attribute.attributeType), forKey: name)
        }
        for (name, relationship) in entity.relationshipsByName where !relationship.isToMany {
            guard case .uuid(let targetID) = record["rel:\(name)"] ?? .null else { continue }
            relationships.append((object, name, targetID, relationship.destinationEntity?.name ?? ""))
        }
        for (name, relationship) in entity.relationshipsByName where relationship.isToMany {
            guard case .string(let json) = record["relm:\(name)"] ?? .null,
                  let data = json.data(using: .utf8),
                  let values = try? JSONDecoder().decode([SyncValue].self, from: data) else { continue }
            let ids = values.compactMap {
                if case .uuid(let id) = $0 { return id }
                return nil
            }
            toMany.append((object, name, ids, relationship.destinationEntity?.name ?? ""))
        }
    }

    public static func nativeValue(_ value: SyncValue, attributeType: NSAttributeType) -> Any? {
        switch (value, attributeType) {
        case (.string(let v), .stringAttributeType): v
        case (.int(let v), .integer16AttributeType): Int32(truncatingIfNeeded: v)
        case (.int(let v), .integer32AttributeType): Int32(truncatingIfNeeded: v)
        case (.int(let v), .integer64AttributeType): v
        case (.double(let v), .doubleAttributeType): v
        case (.double(let v), .floatAttributeType): Float(v)
        case (.double(let v), .decimalAttributeType): NSDecimalNumber(value: v)
        case (.bool(let v), .booleanAttributeType): v
        case (.date(let v), .dateAttributeType): v
        case (.uuid(let v), .UUIDAttributeType): v
        case (.data(let v), .binaryDataAttributeType): v
        case (.null, _): nil
        // Scalars stored as NSNumber in Core Data accept Int64/Double too.
        case (.int(let v), .doubleAttributeType), (.int(let v), .floatAttributeType), (.int(let v), .decimalAttributeType):
            Double(v)
        case (.double(let v), .integer16AttributeType), (.double(let v), .integer32AttributeType), (.double(let v), .integer64AttributeType):
            Int64(v)
        default: nil
        }
    }

    static func findByID(_ id: UUID, entityName: String, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func fetchTombstones(_ context: NSManagedObjectContext) throws -> [String: Date] {
        let request = NSFetchRequest<DeletionLogMO>(entityName: "DeletionLog")
        var result: [String: Date] = [:]
        for entry in try context.fetch(request) {
            let key = "\(entry.recordEntity)/\(entry.recordID.uuidString)"
            if let existing = result[key] {
                result[key] = max(existing, entry.deletedAt)
            } else {
                result[key] = entry.deletedAt
            }
        }
        return result
    }
}
