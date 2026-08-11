import Foundation

struct BackupPayload: Codable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let exportedAt: Date
    let settings: AppSettingsSnapshot
    let venues: [VenueBackup]
    let entries: [EntryBackup]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        exportedAt: Date,
        settings: AppSettingsSnapshot,
        venues: [VenueBackup],
        entries: [EntryBackup]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.settings = settings
        self.venues = venues
        self.entries = entries
    }
}

struct VenueBackup: Codable, Sendable {
    let id: UUID
    let mapItemIdentifier: String?
    let venueIdentity: String
    let name: String
    let formattedAddress: String
    let latitude: Double
    let longitude: Double
}

struct EntryBackup: Codable, Sendable {
    let id: UUID
    let venueID: UUID
    let createdAt: Date
    let currentRatingDate: Date
    let lastModifiedAt: Date
    let currentRating: RatingSnapshot
    let notesData: Data
    let photoFilename: String?
    let photoData: Data?
    let revisions: [RevisionBackup]
}

struct RevisionBackup: Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let rating: RatingSnapshot
}

struct LegacyBackupPayloadV1: Codable, Sendable {
    let schemaVersion: Int
    let exportedAt: Date
    let settings: AppSettingsSnapshot
    let entries: [LegacyEntryBackupV1]

    func upgraded() -> BackupPayload {
        let sorted = entries.sorted { $0.id.uuidString < $1.id.uuidString }
        var venueIDs: [String: UUID] = [:]
        var venues: [VenueBackup] = []
        var upgradedEntries: [EntryBackup] = []

        for entry in sorted {
            let venueID: UUID
            if let existing = venueIDs[entry.venueIdentity] {
                venueID = existing
            } else {
                venueID = entry.id
                venueIDs[entry.venueIdentity] = venueID
                venues.append(VenueBackup(
                    id: venueID,
                    mapItemIdentifier: entry.mapItemIdentifier,
                    venueIdentity: entry.venueIdentity,
                    name: entry.venueName,
                    formattedAddress: entry.formattedAddress,
                    latitude: entry.latitude,
                    longitude: entry.longitude
                ))
            }
            upgradedEntries.append(EntryBackup(
                id: entry.id,
                venueID: venueID,
                createdAt: entry.createdAt,
                currentRatingDate: entry.currentRatingDate,
                lastModifiedAt: entry.lastModifiedAt,
                currentRating: entry.currentRating,
                notesData: entry.notesData,
                photoFilename: entry.photoFilename,
                photoData: entry.photoData,
                revisions: entry.revisions
            ))
        }

        return BackupPayload(
            exportedAt: exportedAt,
            settings: settings,
            venues: venues,
            entries: upgradedEntries
        )
    }
}

struct LegacyEntryBackupV1: Codable, Sendable {
    let id: UUID
    let venueIdentity: String
    let mapItemIdentifier: String?
    let venueName: String
    let formattedAddress: String
    let latitude: Double
    let longitude: Double
    let createdAt: Date
    let currentRatingDate: Date
    let lastModifiedAt: Date
    let currentRating: RatingSnapshot
    let notesData: Data
    let photoFilename: String?
    let photoData: Data?
    let revisions: [RevisionBackup]
}

struct BackupHeader: Decodable {
    let schemaVersion: Int
}
