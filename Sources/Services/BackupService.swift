import Foundation
import Observation
import os
import SwiftData
import UIKit
import UniformTypeIdentifiers

extension UTType {
    static let parmaBackup = UTType(exportedAs: "com.fergohamish.parmamaster.backup", conformingTo: .json)
}

/// Everything an `EntryBackup` needs except the photo bytes, which are read
/// off the main actor inside the detached export task (audit B-06).
private struct PendingEntryBackup: Sendable {
    let id: UUID
    let venueID: UUID
    let createdAt: Date
    let currentRatingDate: Date
    let lastModifiedAt: Date
    let currentRating: RatingSnapshot
    let notesData: Data
    let photoFilename: String?
    let revisions: [RevisionBackup]
}

@MainActor
@Observable
final class BackupService {
    private static let bookmarkKey = "ParmaMaster.BackupDirectoryBookmark"
    private static let lastBackupKey = "ParmaMaster.LastSuccessfulBackup"
    private static let lastChangeKey = "ParmaMaster.LastDataChange"

    private let defaults: UserDefaults
    private var context: ModelContext?
    private var settings: AppSettings?
    private var photoStore: PhotoStore?
    private var debounceTask: Task<Void, Never>?
    var dataDidChange: (() -> Void)?

    var isDirty = false
    var isWorking = false
    var lastSuccessfulBackup: Date?
    var statusMessage: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastSuccessfulBackup = defaults.object(forKey: Self.lastBackupKey) as? Date
        // A change marked before a force-quit must survive the relaunch, or
        // the automatic backup for it is silently lost forever.
        if let lastChange = defaults.object(forKey: Self.lastChangeKey) as? Date,
           lastChange > (lastSuccessfulBackup ?? .distantPast) {
            isDirty = true
        }
    }

    var hasBackupLocation: Bool {
        defaults.data(forKey: Self.bookmarkKey) != nil
    }

    func configure(context: ModelContext, settings: AppSettings, photoStore: PhotoStore) {
        self.context = context
        self.settings = settings
        self.photoStore = photoStore
        settings.changeHandler = { [weak self] in self?.markDirty() }
    }

    func chooseBackupDirectory(_ url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: Self.bookmarkKey)
        statusMessage = "Backup location selected."
    }

    func clearBackupDirectory() {
        defaults.removeObject(forKey: Self.bookmarkKey)
        defaults.removeObject(forKey: Self.lastBackupKey)
        lastSuccessfulBackup = nil
        statusMessage = nil
    }

    func markDirty() {
        isDirty = true
        defaults.set(Date.now, forKey: Self.lastChangeKey)
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: BackupTuning.dirtyDebounce)
            guard !Task.isCancelled else { return }
            await self?.performAutomaticBackupIfNeeded()
        }
    }

    func performAutomaticBackupIfNeeded() async {
        guard isDirty,
              !isWorking,
              let settings,
              settings.automaticBackupsEnabled,
              hasBackupLocation,
              lastSuccessfulBackup.map({ Date.now.timeIntervalSince($0) >= BackupTuning.minimumAutomaticInterval }) ?? true
        else { return }

        // Assertion so iOS grants time when this fires on backgrounding (audit B-06).
        let taskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        defer {
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
            }
        }

        do {
            try await backupNow()
        } catch {
            AppLog.backup.error("Automatic backup failed: \(error.localizedDescription, privacy: .public)")
            statusMessage = "Automatic backup failed. Open Backup & Reset to check the destination."
        }
    }

    func backupNow() async throws {
        guard let context, let settings, let photoStore else { throw BackupError.notReady }
        let directory = try resolvedDirectoryURL()
        let accessing = directory.startAccessingSecurityScopedResource()
        defer { if accessing { directory.stopAccessingSecurityScopedResource() } }

        isWorking = true
        defer { isWorking = false }

        let entries = try context.fetch(FetchDescriptor<ParmaEntry>())
        let venues = try context.fetch(FetchDescriptor<Venue>())
        let settingsSnapshot = settings.snapshot
        let exportedAt = Date.now
        let venueBackups = venues.map { venue in
            VenueBackup(
                id: venue.id,
                mapItemIdentifier: venue.mapItemIdentifier,
                venueIdentity: venue.venueIdentity,
                name: venue.name,
                formattedAddress: venue.formattedAddress,
                latitude: venue.latitude,
                longitude: venue.longitude,
                locality: venue.locality,
                excludedFromRerun: venue.excludedFromRerun
            )
        }
        let pendingEntries = entries.map { entry in
            PendingEntryBackup(
                id: entry.id,
                venueID: entry.venue?.id ?? entry.id,
                createdAt: entry.createdAt,
                currentRatingDate: entry.currentRatingDate,
                lastModifiedAt: entry.lastModifiedAt,
                currentRating: entry.currentRating,
                notesData: entry.notesData,
                photoFilename: entry.photoFilename,
                revisions: entry.sortedRevisions.map {
                    RevisionBackup(id: $0.id, timestamp: $0.timestamp, rating: $0.rating)
                }
            )
        }
        let diskIO = photoStore.diskIO
        let destination = directory.appending(path: BackupTuning.backupFilename)
        let temporary = directory.appending(path: BackupTuning.temporaryFilename)

        // Photo reads, JSON encode and the coordinated write happen off the
        // main actor; only Sendable values cross into the task (audit B-06).
        try await Task.detached(priority: .utility) {
            let payload = BackupPayload(
                exportedAt: exportedAt,
                settings: settingsSnapshot,
                venues: venueBackups,
                entries: pendingEntries.map { pending in
                    EntryBackup(
                        id: pending.id,
                        venueID: pending.venueID,
                        createdAt: pending.createdAt,
                        currentRatingDate: pending.currentRatingDate,
                        lastModifiedAt: pending.lastModifiedAt,
                        currentRating: pending.currentRating,
                        notesData: pending.notesData,
                        photoFilename: pending.photoFilename,
                        photoData: pending.photoFilename.flatMap { diskIO.data(for: $0) },
                        revisions: pending.revisions
                    )
                }
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)

            var coordinationError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { coordinatedURL in
                do {
                    do {
                        try data.write(to: temporary, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    } catch {
                        // Some File Provider volumes reject protection classes (audit S-01).
                        AppLog.backup.notice("Protected backup write failed, retrying unprotected: \(error.localizedDescription, privacy: .public)")
                        try data.write(to: temporary, options: [.atomic])
                    }
                    if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                        _ = try FileManager.default.replaceItemAt(coordinatedURL, withItemAt: temporary)
                    } else {
                        try FileManager.default.moveItem(at: temporary, to: coordinatedURL)
                    }
                } catch {
                    writeError = error
                    try? FileManager.default.removeItem(at: temporary)
                }
            }
            if let coordinationError { throw coordinationError }
            if let writeError { throw writeError }
        }.value

        let now = Date.now
        defaults.set(now, forKey: Self.lastBackupKey)
        lastSuccessfulBackup = now
        isDirty = false
        statusMessage = "Backup completed successfully."
    }

    func restore(from source: URL) async throws {
        guard let context, let settings, let photoStore else { throw BackupError.notReady }
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        isWorking = true
        defer { isWorking = false }

        // Coordinated read + JSON decode off the main actor; model writes
        // stay on the MainActor below (audit B-06).
        let payload = try await Task.detached(priority: .utility) { () throws -> BackupPayload in
            var coordinationError: NSError?
            var readData: Data?
            var readError: Error?
            NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { coordinatedURL in
                do { readData = try Data(contentsOf: coordinatedURL) }
                catch { readError = error }
            }
            if let coordinationError { throw coordinationError }
            if let readError { throw readError }
            guard let readData else { throw BackupError.corrupt }

            do {
                let backupDecoder = JSONDecoder()
                backupDecoder.dateDecodingStrategy = .iso8601
                let header = try backupDecoder.decode(BackupHeader.self, from: readData)
                switch header.schemaVersion {
                case 1:
                    return try backupDecoder.decode(LegacyBackupPayloadV1.self, from: readData).upgraded()
                case BackupPayload.currentSchemaVersion:
                    return try backupDecoder.decode(BackupPayload.self, from: readData)
                default:
                    throw BackupError.unsupportedSchema
                }
            } catch let error as BackupError {
                throw error
            } catch {
                throw BackupError.corrupt
            }
        }.value

        guard payload.entries.allSatisfy({ $0.currentRating.hasValidScores }) else { throw BackupError.corrupt }
        guard Set(payload.venues.map(\.id)).count == payload.venues.count,
              payload.entries.allSatisfy({ entry in payload.venues.contains(where: { $0.id == entry.venueID }) })
        else { throw BackupError.corrupt }

        try LocalParmaRepository().reset(photoStore: photoStore, in: context)
        var restoredVenues: [UUID: Venue] = [:]
        for backup in payload.venues {
            let venue = Venue(
                id: backup.id,
                mapItemIdentifier: backup.mapItemIdentifier,
                venueIdentity: backup.venueIdentity,
                name: backup.name,
                formattedAddress: backup.formattedAddress,
                latitude: backup.latitude,
                longitude: backup.longitude,
                locality: backup.locality,
                excludedFromRerun: backup.excludedFromRerun
            )
            restoredVenues[backup.id] = venue
            context.insert(venue)
        }
        for backup in payload.entries {
            if let filename = backup.photoFilename, let photoData = backup.photoData {
                try photoStore.restore(data: photoData, filename: filename)
            }
            let revisions = backup.revisions.map {
                RatingRevision(id: $0.id, timestamp: $0.timestamp, rating: $0.rating)
            }
            let notes = (try? JSONDecoder().decode(AttributedString.self, from: backup.notesData)) ?? AttributedString()
            guard let venue = restoredVenues[backup.venueID] else { throw BackupError.corrupt }
            let entry = ParmaEntry(
                id: backup.id,
                venue: venue,
                createdAt: backup.createdAt,
                currentRatingDate: backup.currentRatingDate,
                lastModifiedAt: backup.lastModifiedAt,
                rating: backup.currentRating,
                notes: notes,
                photoFilename: backup.photoFilename,
                revisions: revisions
            )
            for revision in revisions { revision.entry = entry }
            context.insert(entry)
        }
        try context.save()
        settings.apply(payload.settings)
        isDirty = false
        statusMessage = "Backup restored successfully."
        dataDidChange?()
    }

    private func resolvedDirectoryURL() throws -> URL {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { throw BackupError.noDirectory }
        var isStale = false
        let url = try URL(resolvingBookmarkData: data, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale)
        if isStale {
            try chooseBackupDirectory(url)
        }
        return url
    }
}

enum BackupError: LocalizedError {
    case notReady
    case noDirectory
    case corrupt
    case unsupportedSchema
    case validationFailed

    var errorDescription: String? {
        switch self {
        case .notReady: "Backup services are still starting. Please try again."
        case .noDirectory: "Choose a backup location before creating a backup."
        case .corrupt: "This backup is damaged or is not a valid Parma Master backup."
        case .unsupportedSchema: "This backup was created by an unsupported version of Parma Master."
        case .validationFailed: "The backup could not be validated, so the previous backup was left unchanged."
        }
    }
}
