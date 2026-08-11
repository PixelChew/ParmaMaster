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

enum ParmaSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
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
        var locality: String?
        var excludedFromRerun: Bool

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
            locality: String? = nil,
            excludedFromRerun: Bool = false,
            entries: [ParmaEntry] = []
        ) {
            self.id = id
            self.mapItemIdentifier = mapItemIdentifier
            self.venueIdentity = venueIdentity
            self.name = name
            self.formattedAddress = formattedAddress
            self.latitude = latitude
            self.longitude = longitude
            self.locality = locality
            self.excludedFromRerun = excludedFromRerun
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

        // Decoded forms are memoised because rating and notes JSON was
        // previously decoded on every access, multiplying into thousands of
        // decodes per render across sorting, cards, search and the map.
        @Transient private var ratingCache = DecodedJSONCache<RatingSnapshot>()
        @Transient private var notesCache = DecodedJSONCache<AttributedString>()

        var currentRating: RatingSnapshot {
            get {
                ratingCache.value(for: currentRatingData) {
                    Self.decode(RatingSnapshot.self, from: $0) ?? .blank(configuration: .default)
                }
            }
            set {
                currentRatingData = Self.encode(newValue)
                ratingCache.invalidate()
            }
        }

        var notes: AttributedString {
            get {
                notesCache.value(for: notesData) {
                    Self.decode(AttributedString.self, from: $0) ?? AttributedString()
                }
            }
            set {
                notesData = Self.encode(newValue)
                notesCache.invalidate()
            }
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

        @Transient private var ratingCache = DecodedJSONCache<RatingSnapshot>()

        init(id: UUID = UUID(), timestamp: Date, rating: RatingSnapshot, entry: ParmaEntry? = nil) {
            self.id = id
            self.timestamp = timestamp
            self.ratingData = (try? JSONEncoder().encode(rating)) ?? Data()
            self.entry = entry
        }

        var rating: RatingSnapshot {
            get {
                ratingCache.value(for: ratingData) {
                    (try? JSONDecoder().decode(RatingSnapshot.self, from: $0)) ?? .blank(configuration: .default)
                }
            }
            set {
                ratingData = (try? JSONEncoder().encode(newValue)) ?? Data()
                ratingCache.invalidate()
            }
        }
    }
}

typealias Venue = ParmaSchemaV3.Venue
typealias ParmaEntry = ParmaSchemaV3.ParmaEntry
typealias RatingRevision = ParmaSchemaV3.RatingRevision

enum ParmaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ParmaSchemaV1.self, ParmaSchemaV2.self, ParmaSchemaV3.self] }
    static var stages: [MigrationStage] { [migrateV1toV2, migrateV2toV3] }

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

    private struct VenueRecord: Sendable {
        let id: UUID
        let mapItemIdentifier: String?
        let venueIdentity: String
        let name: String
        let formattedAddress: String
        let latitude: Double
        let longitude: Double
    }

    private struct V2EntryRecord: Sendable {
        let id: UUID
        let venueIdentity: String
        let createdAt: Date
        let currentRatingDate: Date
        let lastModifiedAt: Date
        let currentRatingData: Data
        let notesData: Data
        let photoFilename: String?
        let revisions: [RevisionRecord]
    }

    // Lock-guarded rather than `nonisolated(unsafe)`: migration stages run
    // once and serially, but the compiler cannot see that execution guarantee.
    private static let migrationRecords = LockIsolated<[EntryRecord]>([])
    private static let v2VenueRecords = LockIsolated<[VenueRecord]>([])
    private static let v2EntryRecords = LockIsolated<[V2EntryRecord]>([])

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: ParmaSchemaV1.self,
        toVersion: ParmaSchemaV2.self,
        willMigrate: { context in
            let oldEntries = try context.fetch(FetchDescriptor<ParmaSchemaV1.ParmaEntry>())
            let records = oldEntries.map { entry in
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
            migrationRecords.withLock { $0 = records }
            for entry in oldEntries { context.delete(entry) }
            try context.save()
        },
        didMigrate: { context in
            let records = migrationRecords.withLock { $0 }.sorted { $0.id.uuidString < $1.id.uuidString }
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
            migrationRecords.withLock { $0.removeAll(keepingCapacity: false) }
        }
    )

    static let migrateV2toV3 = MigrationStage.custom(
        fromVersion: ParmaSchemaV2.self,
        toVersion: ParmaSchemaV3.self,
        willMigrate: { context in
            let oldVenues = try context.fetch(FetchDescriptor<ParmaSchemaV2.Venue>())
            let oldEntries = try context.fetch(FetchDescriptor<ParmaSchemaV2.ParmaEntry>())

            let venueRecords = oldVenues.map { venue in
                VenueRecord(
                    id: venue.id,
                    mapItemIdentifier: venue.mapItemIdentifier,
                    venueIdentity: venue.venueIdentity,
                    name: venue.name,
                    formattedAddress: venue.formattedAddress,
                    latitude: venue.latitude,
                    longitude: venue.longitude
                )
            }
            v2VenueRecords.withLock { $0 = venueRecords }

            let entryRecords = oldEntries.map { entry in
                V2EntryRecord(
                    id: entry.id,
                    venueIdentity: entry.venue?.venueIdentity ?? "",
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
            v2EntryRecords.withLock { $0 = entryRecords }

            for entry in oldEntries { context.delete(entry) }
            for venue in oldVenues { context.delete(venue) }
            try context.save()
        },
        didMigrate: { context in
            var venuesByIdentity: [String: ParmaSchemaV3.Venue] = [:]

            for record in v2VenueRecords.withLock({ $0 }).sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                let venue = ParmaSchemaV3.Venue(
                    id: record.id,
                    mapItemIdentifier: record.mapItemIdentifier,
                    venueIdentity: record.venueIdentity,
                    name: record.name,
                    formattedAddress: record.formattedAddress,
                    latitude: record.latitude,
                    longitude: record.longitude,
                    locality: nil,
                    excludedFromRerun: false
                )
                venuesByIdentity[record.venueIdentity] = venue
                context.insert(venue)
            }

            for record in v2EntryRecords.withLock({ $0 }).sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                guard let venue = venuesByIdentity[record.venueIdentity] else { continue }

                let revisions = record.revisions.map { revision -> ParmaSchemaV3.RatingRevision in
                    let rating = (try? JSONDecoder().decode(RatingSnapshot.self, from: revision.ratingData))
                        ?? .blank(configuration: .default)
                    return ParmaSchemaV3.RatingRevision(id: revision.id, timestamp: revision.timestamp, rating: rating)
                }
                let rating = (try? JSONDecoder().decode(RatingSnapshot.self, from: record.currentRatingData))
                    ?? .blank(configuration: .default)
                let notes = (try? JSONDecoder().decode(AttributedString.self, from: record.notesData))
                    ?? AttributedString()
                let entry = ParmaSchemaV3.ParmaEntry(
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
            v2VenueRecords.withLock { $0.removeAll(keepingCapacity: false) }
            v2EntryRecords.withLock { $0.removeAll(keepingCapacity: false) }
        }
    )
}
