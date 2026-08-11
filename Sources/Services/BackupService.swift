import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    static let parmaBackup = UTType(exportedAs: "com.fergohamish.parmamaster.backup", conformingTo: .json)
}

@MainActor
@Observable
final class BackupService {
    private static let bookmarkKey = "ParmaMaster.BackupDirectoryBookmark"
    private static let lastBackupKey = "ParmaMaster.LastSuccessfulBackup"
    private static let minimumAutomaticInterval: TimeInterval = 5 * 60

    private let defaults: UserDefaults
    private var context: ModelContext?
    private var settings: AppSettings?
    private var photoStore: PhotoStore?
    private var debounceTask: Task<Void, Never>?

    var isDirty = false
    var isWorking = false
    var lastSuccessfulBackup: Date?
    var statusMessage: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastSuccessfulBackup = defaults.object(forKey: Self.lastBackupKey) as? Date
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
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await self?.performAutomaticBackupIfNeeded()
        }
    }

    func performAutomaticBackupIfNeeded() async {
        guard isDirty,
              let settings,
              settings.automaticBackupsEnabled,
              hasBackupLocation,
              lastSuccessfulBackup.map({ Date.now.timeIntervalSince($0) >= Self.minimumAutomaticInterval }) ?? true
        else { return }
        try? backupNow()
    }

    func backupNow() throws {
        guard let context, let settings, let photoStore else { throw BackupError.notReady }
        let directory = try resolvedDirectoryURL()
        let accessing = directory.startAccessingSecurityScopedResource()
        defer { if accessing { directory.stopAccessingSecurityScopedResource() } }

        isWorking = true
        defer { isWorking = false }

        let entries = try context.fetch(FetchDescriptor<ParmaEntry>())
        let venues = try context.fetch(FetchDescriptor<Venue>())
        let payload = BackupPayload(
            exportedAt: .now,
            settings: settings.snapshot,
            venues: venues.map { venue in
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
            },
            entries: entries.map { entry in
                EntryBackup(
                    id: entry.id,
                    venueID: entry.venue?.id ?? entry.id,
                    createdAt: entry.createdAt,
                    currentRatingDate: entry.currentRatingDate,
                    lastModifiedAt: entry.lastModifiedAt,
                    currentRating: entry.currentRating,
                    notesData: entry.notesData,
                    photoFilename: entry.photoFilename,
                    photoData: entry.photoFilename.flatMap(photoStore.data(for:)),
                    revisions: entry.sortedRevisions.map {
                        RevisionBackup(id: $0.id, timestamp: $0.timestamp, rating: $0.rating)
                    }
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        guard (try? decoder().decode(BackupPayload.self, from: data)) != nil else { throw BackupError.validationFailed }

        let destination = directory.appending(path: "Parma Master.parmabackup")
        let temporary = directory.appending(path: ".Parma Master.parmabackup.tmp")
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                try data.write(to: temporary, options: .atomic)
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

        let now = Date.now
        defaults.set(now, forKey: Self.lastBackupKey)
        lastSuccessfulBackup = now
        isDirty = false
        statusMessage = "Backup completed successfully."
    }

    func restore(from source: URL) throws {
        guard let context, let settings, let photoStore else { throw BackupError.notReady }
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        isWorking = true
        defer { isWorking = false }

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

        let payload: BackupPayload
        do {
            let backupDecoder = decoder()
            let header = try backupDecoder.decode(BackupHeader.self, from: readData)
            switch header.schemaVersion {
            case 1:
                payload = try backupDecoder.decode(LegacyBackupPayloadV1.self, from: readData).upgraded()
            case BackupPayload.currentSchemaVersion:
                payload = try backupDecoder.decode(BackupPayload.self, from: readData)
            default:
                throw BackupError.unsupportedSchema
            }
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.corrupt
        }
        guard payload.entries.allSatisfy({ $0.currentRating.hasValidScores }) else { throw BackupError.corrupt }
        guard Set(payload.venues.map(\.id)).count == payload.venues.count,
              payload.entries.allSatisfy({ entry in payload.venues.contains(where: { $0.id == entry.venueID }) })
        else { throw BackupError.corrupt }

        try EntryRepository.reset(photoStore: photoStore, in: context)
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

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
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
