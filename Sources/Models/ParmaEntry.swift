import Foundation
import SwiftData

enum ParmaSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [ParmaEntry.self, RatingRevision.self] }

    @Model
    final class ParmaEntry {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var venueIdentity: String
        var mapItemIdentifier: String?
        var venueName: String
        var formattedAddress: String
        var latitude: Double
        var longitude: Double
        var createdAt: Date
        var currentRatingDate: Date
        var lastModifiedAt: Date
        var currentRatingData: Data
        var notesData: Data
        var photoFilename: String?

        @Relationship(deleteRule: .cascade, inverse: \RatingRevision.entry)
        var revisions: [RatingRevision]

        init(
            id: UUID,
            venueIdentity: String,
            mapItemIdentifier: String?,
            venueName: String,
            formattedAddress: String,
            latitude: Double,
            longitude: Double,
            createdAt: Date,
            currentRatingDate: Date,
            lastModifiedAt: Date,
            currentRatingData: Data,
            notesData: Data,
            photoFilename: String?,
            revisions: [RatingRevision]
        ) {
            self.id = id
            self.venueIdentity = venueIdentity
            self.mapItemIdentifier = mapItemIdentifier
            self.venueName = venueName
            self.formattedAddress = formattedAddress
            self.latitude = latitude
            self.longitude = longitude
            self.createdAt = createdAt
            self.currentRatingDate = currentRatingDate
            self.lastModifiedAt = lastModifiedAt
            self.currentRatingData = currentRatingData
            self.notesData = notesData
            self.photoFilename = photoFilename
            self.revisions = revisions
        }
    }

    @Model
    final class RatingRevision {
        @Attribute(.unique) var id: UUID
        var timestamp: Date
        var ratingData: Data
        var entry: ParmaEntry?

        init(id: UUID, timestamp: Date, ratingData: Data, entry: ParmaEntry? = nil) {
            self.id = id
            self.timestamp = timestamp
            self.ratingData = ratingData
            self.entry = entry
        }
    }
}

enum ParmaSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Venue.self, ParmaEntry.self, RatingRevision.self] }

    @Model
    final class Venue {
        @Attribute(.unique) var id: UUID
        var mapItemIdentifier: String?
        @Attribute(.unique) var venueIdentity: String
        var name: String
        var formattedAddress: String
        var latitude: Double
        var longitude: Double

        @Relationship(deleteRule: .nullify, inverse: \ParmaEntry.venue)
        var entries: [ParmaEntry]

        init(
            id: UUID = UUID(),
            mapItemIdentifier: String?,
            venueIdentity: String,
            name: String,
            formattedAddress: String,
            latitude: Double,
            longitude: Double,
            entries: [ParmaEntry] = []
        ) {
            self.id = id
            self.mapItemIdentifier = mapItemIdentifier
            self.venueIdentity = venueIdentity
            self.name = name
            self.formattedAddress = formattedAddress
            self.latitude = latitude
            self.longitude = longitude
            self.entries = entries
        }
    }

    @Model
    final class ParmaEntry {
        @Attribute(.unique) var id: UUID
        var venue: Venue?
        var createdAt: Date
        var currentRatingDate: Date
        var lastModifiedAt: Date
        var currentRatingData: Data
        var notesData: Data
        var photoFilename: String?

        @Relationship(deleteRule: .cascade, inverse: \RatingRevision.entry)
        var revisions: [RatingRevision]

        init(
            id: UUID = UUID(),
            venue: Venue,
            createdAt: Date = .now,
            currentRatingDate: Date = .now,
            lastModifiedAt: Date = .now,
            rating: RatingSnapshot,
            notes: AttributedString = AttributedString(),
            photoFilename: String? = nil,
            revisions: [RatingRevision] = []
        ) {
            self.id = id
            self.venue = venue
            self.createdAt = createdAt
            self.currentRatingDate = currentRatingDate
            self.lastModifiedAt = lastModifiedAt
            self.currentRatingData = Self.encode(rating)
            self.notesData = Self.encode(notes)
            self.photoFilename = photoFilename
            self.revisions = revisions
        }

        convenience init(
            id: UUID = UUID(),
            venueIdentity: String,
            mapItemIdentifier: String?,
            venueName: String,
            formattedAddress: String,
            latitude: Double,
            longitude: Double,
            createdAt: Date = .now,
            currentRatingDate: Date = .now,
            lastModifiedAt: Date = .now,
            rating: RatingSnapshot,
            notes: AttributedString = AttributedString(),
            photoFilename: String? = nil,
            revisions: [RatingRevision] = []
        ) {
            self.init(
                id: id,
                venue: Venue(
                    mapItemIdentifier: mapItemIdentifier,
                    venueIdentity: venueIdentity,
                    name: venueName,
                    formattedAddress: formattedAddress,
                    latitude: latitude,
                    longitude: longitude
                ),
                createdAt: createdAt,
                currentRatingDate: currentRatingDate,
                lastModifiedAt: lastModifiedAt,
                rating: rating,
                notes: notes,
                photoFilename: photoFilename,
                revisions: revisions
            )
        }

        var venueIdentity: String { venue?.venueIdentity ?? "" }
        var mapItemIdentifier: String? {
            get { venue?.mapItemIdentifier }
            set { venue?.mapItemIdentifier = newValue }
        }
        var venueName: String {
            get { venue?.name ?? "Unknown venue" }
            set { venue?.name = newValue }
        }
        var formattedAddress: String {
            get { venue?.formattedAddress ?? "Address unavailable" }
            set { venue?.formattedAddress = newValue }
        }
        var latitude: Double {
            get { venue?.latitude ?? 0 }
            set { venue?.latitude = newValue }
        }
        var longitude: Double {
            get { venue?.longitude ?? 0 }
            set { venue?.longitude = newValue }
        }

        var currentRating: RatingSnapshot {
            get { Self.decode(RatingSnapshot.self, from: currentRatingData) ?? .blank(configuration: .default) }
            set { currentRatingData = Self.encode(newValue) }
        }

        var notes: AttributedString {
            get { Self.decode(AttributedString.self, from: notesData) ?? AttributedString() }
            set { notesData = Self.encode(newValue) }
        }

        var searchableNotes: String { String(notes.characters) }
        var sortedRevisions: [RatingRevision] { revisions.sorted { $0.timestamp > $1.timestamp } }

        private static func encode<T: Encodable>(_ value: T) -> Data {
            (try? JSONEncoder().encode(value)) ?? Data()
        }

        private static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
            try? JSONDecoder().decode(type, from: data)
        }
    }

    @Model
    final class RatingRevision {
        @Attribute(.unique) var id: UUID
        var timestamp: Date
        var ratingData: Data
        var entry: ParmaEntry?

        init(id: UUID = UUID(), timestamp: Date, rating: RatingSnapshot, entry: ParmaEntry? = nil) {
            self.id = id
            self.timestamp = timestamp
            self.ratingData = (try? JSONEncoder().encode(rating)) ?? Data()
            self.entry = entry
        }

        var rating: RatingSnapshot {
            get { (try? JSONDecoder().decode(RatingSnapshot.self, from: ratingData)) ?? .blank(configuration: .default) }
            set { ratingData = (try? JSONEncoder().encode(newValue)) ?? Data() }
        }
    }
}

typealias Venue = ParmaSchemaV2.Venue
typealias ParmaEntry = ParmaSchemaV2.ParmaEntry
typealias RatingRevision = ParmaSchemaV2.RatingRevision

enum ParmaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ParmaSchemaV1.self, ParmaSchemaV2.self] }
    static var stages: [MigrationStage] { [migrateV1toV2] }

    private struct RevisionRecord: Sendable {
        let id: UUID
        let timestamp: Date
        let ratingData: Data
    }

    private struct EntryRecord: Sendable {
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
        let currentRatingData: Data
        let notesData: Data
        let photoFilename: String?
        let revisions: [RevisionRecord]
    }

    nonisolated(unsafe) private static var migrationRecords: [EntryRecord] = []

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: ParmaSchemaV1.self,
        toVersion: ParmaSchemaV2.self,
        willMigrate: { context in
            let oldEntries = try context.fetch(FetchDescriptor<ParmaSchemaV1.ParmaEntry>())
            migrationRecords = oldEntries.map { entry in
                EntryRecord(
                    id: entry.id,
                    venueIdentity: entry.venueIdentity,
                    mapItemIdentifier: entry.mapItemIdentifier,
                    venueName: entry.venueName,
                    formattedAddress: entry.formattedAddress,
                    latitude: entry.latitude,
                    longitude: entry.longitude,
                    createdAt: entry.createdAt,
                    currentRatingDate: entry.currentRatingDate,
                    lastModifiedAt: entry.lastModifiedAt,
                    currentRatingData: entry.currentRatingData,
                    notesData: entry.notesData,
                    photoFilename: entry.photoFilename,
                    revisions: entry.revisions.map {
                        RevisionRecord(id: $0.id, timestamp: $0.timestamp, ratingData: $0.ratingData)
                    }
                )
            }
            for entry in oldEntries { context.delete(entry) }
            try context.save()
        },
        didMigrate: { context in
            let records = migrationRecords.sorted { $0.id.uuidString < $1.id.uuidString }
            var venuesByIdentity: [String: ParmaSchemaV2.Venue] = [:]

            for record in records {
                let venue: ParmaSchemaV2.Venue
                if let existing = venuesByIdentity[record.venueIdentity] {
                    venue = existing
                } else {
                    venue = ParmaSchemaV2.Venue(
                        id: record.id,
                        mapItemIdentifier: record.mapItemIdentifier,
                        venueIdentity: record.venueIdentity,
                        name: record.venueName,
                        formattedAddress: record.formattedAddress,
                        latitude: record.latitude,
                        longitude: record.longitude
                    )
                    venuesByIdentity[record.venueIdentity] = venue
                    context.insert(venue)
                }

                let revisions = record.revisions.map { revision -> ParmaSchemaV2.RatingRevision in
                    let rating = (try? JSONDecoder().decode(RatingSnapshot.self, from: revision.ratingData))
                        ?? .blank(configuration: .default)
                    return ParmaSchemaV2.RatingRevision(id: revision.id, timestamp: revision.timestamp, rating: rating)
                }
                let rating = (try? JSONDecoder().decode(RatingSnapshot.self, from: record.currentRatingData))
                    ?? .blank(configuration: .default)
                let notes = (try? JSONDecoder().decode(AttributedString.self, from: record.notesData))
                    ?? AttributedString()
                let entry = ParmaSchemaV2.ParmaEntry(
                    id: record.id,
                    venue: venue,
                    createdAt: record.createdAt,
                    currentRatingDate: record.currentRatingDate,
                    lastModifiedAt: record.lastModifiedAt,
                    rating: rating,
                    notes: notes,
                    photoFilename: record.photoFilename,
                    revisions: revisions
                )
                for revision in revisions { revision.entry = entry }
                context.insert(entry)
            }
            try context.save()
            migrationRecords.removeAll(keepingCapacity: false)
        }
    )
}
