import CoreData
import Foundation
import ProMeDomain

/// Owns the Core Data stack. The view context is used on the main actor;
/// background work goes through dedicated contexts created on demand.
///
/// Store versions are managed by the Core Data model in `Model/` and the
/// migration plan below. Automatic lightweight migration is enabled from
/// day one; larger schema changes get explicit mapping models in a new
/// model version rather than edits to existing ones.
@MainActor
public final class PersistenceController {
    public let container: NSPersistentContainer
    /// The on-disk store location, nil when running purely in memory.
    public let storeURL: URL?

    private final class LoadErrorBox: @unchecked Sendable {
        var error: (any Error)?
    }

    /// Thread-safe stash between the will-save and did-save notifications.
    private final class PendingDeletionBox: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [DeletionRecord] = []

        func append(_ records: [DeletionRecord]) {
            lock.lock()
            defer { lock.unlock() }
            items += records
        }

        func drain() -> [DeletionRecord] {
            lock.lock()
            defer { lock.unlock() }
            let out = items
            items = []
            return out
        }
    }

    private var deletionObservers: [NSObjectProtocol] = []
    private let pendingDeletions = PendingDeletionBox()

    /// Thread-safe singleton for the compiled model. Loading one instance
    /// per controller would register the same managed-object subclasses
    /// against several models ("no unique NSEntityDescription match") and
    /// make parallel in-memory stores incompatible on open.
    private static let modelLock = NSLock()
    private static var cachedModel: NSManagedObjectModel?

    public init(inMemory: Bool = false) throws {
        let model = try Self.loadModel()
        container = NSPersistentContainer(name: "ProMe", managedObjectModel: model)

        if inMemory {
            // An ephemeral SQLite store in a unique temp file: fully
            // isolated per coordinator (parallel tests never share a
            // store) and supporting aggregate GROUP BY fetches, which the
            // plain NSInMemoryStoreType rejects. storeURL stays nil so
            // backup/restore refuse ephemeral stores.
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("ProMe-ephemeral-\(UUID().uuidString).sqlite")
            let description = NSPersistentStoreDescription(url: temp)
            description.type = NSSQLiteStoreType
            description.shouldAddStoreAsynchronously = false
            container.persistentStoreDescriptions = [description]
            Self.pruneEphemeralStores()
            self.storeURL = nil
        } else {
            let storeURL = try Self.defaultStoreURL()
            self.storeURL = storeURL
            let description = NSPersistentStoreDescription(url: storeURL)
            description.type = NSSQLiteStoreType
            description.shouldAddStoreAsynchronously = false
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            container.persistentStoreDescriptions = [description]
        }

        let loadError = LoadErrorBox()
        container.loadPersistentStores { _, error in
            loadError.error = error
        }
        if let error = loadError.error {
            throw DatabaseError.storeLoadFailed(error.localizedDescription)
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        observeDeletions()
    }

    /// Records every successful deletion as a tombstone (DeletionLog) so
    /// device sync can propagate removals. Will-save stashes the deleted
    /// ids; did-save (the deletion actually persisted) writes the log
    /// entries on the view context. Entities without an `id` are ignored.
    private func observeDeletions() {
        let coordinator = container.persistentStoreCoordinator
        nonisolated(unsafe) let viewContext = container.viewContext
        nonisolated(unsafe) let box = pendingDeletions

        deletionObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSManagedObjectContextWillSave, object: nil, queue: nil
        ) { note in
            guard let context = note.object as? NSManagedObjectContext,
                  context.persistentStoreCoordinator === coordinator,
                  !context.deletedObjects.isEmpty else { return }
            let records: [DeletionRecord] = context.deletedObjects.compactMap { object in
                let entityName = object.entity.name ?? ""
                guard entityName != "DeletionLog",
                      let id = object.value(forKey: "id") as? UUID else { return nil }
                return DeletionRecord(entityName: entityName, recordID: id, deletedAt: .now)
            }
            guard !records.isEmpty else { return }
            box.append(records)
        })

        deletionObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSManagedObjectContextDidSave, object: nil, queue: nil
        ) { note in
            guard let context = note.object as? NSManagedObjectContext,
                  context.persistentStoreCoordinator === coordinator else { return }
            let records = box.drain()
            guard !records.isEmpty else { return }
            viewContext.performAndWait {
                for record in records {
                    let entry = DeletionLogMO(context: viewContext)
                    entry.id = UUID()
                    entry.recordEntity = record.entityName
                    entry.recordID = record.recordID
                    entry.deletedAt = record.deletedAt
                }
                try? viewContext.save()
            }
        })
    }

    /// Drops tombstones older than `days` — every live device will have
    /// long since pulled them.
    public func pruneDeletionLog(olderThanDays days: Int = 90) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        let request = NSFetchRequest<DeletionLogMO>(entityName: "DeletionLog")
        request.predicate = NSPredicate(format: "deletedAt < %@", cutoff as NSDate)
        let context = container.viewContext
        for entry in (try? context.fetch(request)) ?? [] {
            context.delete(entry)
        }
        try? context.save()
    }

    /// Loads the compiled model that ships inside this package.
    public static func loadModel() throws -> NSManagedObjectModel {
        Self.modelLock.lock()
        defer { Self.modelLock.unlock() }
        if let cachedModel { return cachedModel }
        guard let url = Bundle.module.url(forResource: "ProMe", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            throw DatabaseError.modelNotFound
        }
        cachedModel = model
        return model
    }

    /// Best-effort cleanup of ephemeral test stores left behind by earlier
    /// runs (the OS clears the temp directory eventually; this keeps it tidy).
    private static func pruneEphemeralStores() {
        let temp = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: temp, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date.now.addingTimeInterval(-86_400)
        for file in contents where file.lastPathComponent.hasPrefix("ProMe-ephemeral-") {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .now
            if modified < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// The on-disk store location inside Application Support.
    public static func defaultStoreURL() throws -> URL {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw DatabaseError.storeLoadFailed("Application Support directory is unavailable.")
        }
        let directory = support.appendingPathComponent("ProMe", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("ProMe.sqlite")
        migrateLegacyStore(to: storeURL)
        return storeURL
    }

    /// One-time move of the pre-rename "ProBill" store so users keep their
    /// data when the app becomes ProMe.
    private static func migrateLegacyStore(to newURL: URL) {
        let legacyDirectory = newURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ProBill", isDirectory: true)
        let legacyStore = legacyDirectory.appendingPathComponent("ProBill.sqlite")
        guard FileManager.default.fileExists(atPath: legacyStore.path),
              !FileManager.default.fileExists(atPath: newURL.path) else { return }
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: legacyStore.path + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try? FileManager.default.copyItem(at: source, to: URL(fileURLWithPath: newURL.path + suffix))
        }
    }

    /// Saves the view context, mapping any failure to a domain error.
    public func saveViewContext() throws {
        let context = container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            throw DatabaseError.saveFailed(error.localizedDescription)
        }
    }
}

// NSManagedObject lacks an Identifiable conformance in this SDK; every
// managed object is uniquely identified by its Core Data id.
extension NSManagedObject: Identifiable {}
