import Foundation
import SwiftData

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
        self.currentRatingData = Self.encode(rating)
        self.notesData = Self.encode(notes)
        self.photoFilename = photoFilename
        self.revisions = revisions
    }

    var currentRating: RatingSnapshot {
        get { Self.decode(RatingSnapshot.self, from: currentRatingData) ?? .blank(configuration: .default) }
        set { currentRatingData = Self.encode(newValue) }
    }

    var notes: AttributedString {
        get { Self.decode(AttributedString.self, from: notesData) ?? AttributedString() }
        set { notesData = Self.encode(newValue) }
    }

    var searchableNotes: String {
        String(notes.characters)
    }

    var sortedRevisions: [RatingRevision] {
        revisions.sorted { $0.timestamp > $1.timestamp }
    }

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
