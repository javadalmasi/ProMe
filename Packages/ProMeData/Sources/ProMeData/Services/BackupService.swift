import CoreData
import Foundation
import ProMeDomain
import SQLite3

/// Manual backup and restore of the whole store. Backups are plain,
/// portable SQLite files in a dated folder; restore swaps the live store
/// through the coordinator and resets the contexts.
@MainActor
public final class BackupService {
    private let controller: PersistenceController
    public init(controller: PersistenceController) {
        self.controller = controller
    }

    public static let storeFileName = "ProMe.sqlite"

    public struct BackupInfo: Identifiable, Equatable {
        public var id: URL { folder }
        public let folder: URL
        public let date: Date
    }

    /// Copies the store (WAL checkpointed) into `folder/ProMe-Backup-<stamp>/`.
    public func backup(to folder: URL) throws -> URL {
        guard let storeURL = controller.storeURL else {
            throw DatabaseError.storeLoadFailed("The store is running in memory and cannot be backed up.")
        }
        let stamp = Self.backupFormatter.string(from: .now)
        let destination = folder.appendingPathComponent("ProMe-Backup-\(stamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        checkpointStore(at: storeURL)

        let suffixes = ["", "-wal", "-shm"]
        for suffix in suffixes {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let target = destination.appendingPathComponent(Self.storeFileName + suffix)
            try FileManager.default.copyItem(at: source, to: target)
        }
        return destination
    }

    /// Replaces the live store with the backup in `backupFolder` and
    /// resets the view context. The UI should refresh all data afterwards.
    public func restore(from backupFolder: URL) throws {
        guard let storeURL = controller.storeURL else {
            throw DatabaseError.storeLoadFailed("The store is running in memory and cannot be restored.")
        }
        let backupFile = backupFolder.appendingPathComponent(Self.storeFileName)
        guard FileManager.default.fileExists(atPath: backupFile.path) else {
            throw DatabaseError.storeLoadFailed("No ProMe.sqlite found in the selected folder.")
        }
        let coordinator = controller.container.persistentStoreCoordinator
        try coordinator.replacePersistentStore(
            at: storeURL,
            destinationOptions: nil,
            withPersistentStoreFrom: backupFile,
            sourceOptions: nil,
            ofType: NSSQLiteStoreType
        )
        controller.container.viewContext.reset()
    }

    /// Known backup folders recorded in UserDefaults, newest first.
    public func recordedBackups() -> [BackupInfo] {
        let paths = UserDefaults.standard.stringArray(forKey: "prome.backup.folders") ?? []
        return paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.appendingPathComponent(Self.storeFileName).path) else {
                return nil
            }
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            let date = attributes?[.creationDate] as? Date ?? .distantPast
            return BackupInfo(folder: url, date: date)
        }
        .sorted { $0.date > $1.date }
    }

    public func recordBackupFolder(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: "prome.backup.folders") ?? []
        if !paths.contains(url.path) {
            paths.insert(url.path, at: 0)
        }
        UserDefaults.standard.set(Array(paths.prefix(20)), forKey: "prome.backup.folders")
    }

    /// Forces SQLite to fold the WAL into the main file so the .sqlite
    /// copy is self-contained. Failures are non-fatal: the WAL file is
    /// copied as well.
    private func checkpointStore(at storeURL: URL) {
        var database: OpaquePointer?
        let path = storeURL.path
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return
        }
        sqlite3_exec(database, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
        sqlite3_close(database)
    }

    static let backupFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()
}
