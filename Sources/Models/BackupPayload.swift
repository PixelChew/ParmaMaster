import Foundation

struct BackupPayload: Codable, Sendable {
    let schemaVersion: Int
    let exportedAt: Date
    let settings: AppSettingsSnapshot
    let entries: [EntryBackup]
}

struct EntryBackup: Codable, Sendable {
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

struct RevisionBackup: Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let rating: RatingSnapshot
}
