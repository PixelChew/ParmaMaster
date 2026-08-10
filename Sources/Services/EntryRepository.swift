import CoreLocation
import Foundation
import SwiftData

@MainActor
enum EntryRepository {
    static func findExisting(for venue: VenueCandidate, in entries: [ParmaEntry]) -> ParmaEntry? {
        entries.first { VenueIdentity.matches(venue, entry: $0) }
    }

    @discardableResult
    static func create(
        venue: VenueCandidate,
        rating: RatingSnapshot,
        notes: AttributedString,
        photoFilename: String?,
        in context: ModelContext
    ) throws -> ParmaEntry {
        guard rating.hasValidScores else { throw EntryRepositoryError.invalidRating }
        let entries = try context.fetch(FetchDescriptor<ParmaEntry>())
        if let existing = findExisting(for: venue, in: entries) {
            return existing
        }

        let entry = ParmaEntry(
            venueIdentity: VenueIdentity.key(for: venue),
            mapItemIdentifier: venue.mapItemIdentifier,
            venueName: venue.name,
            formattedAddress: venue.formattedAddress,
            latitude: venue.latitude,
            longitude: venue.longitude,
            rating: rating,
            notes: notes,
            photoFilename: photoFilename
        )
        context.insert(entry)
        try context.save()
        return entry
    }

    static func update(
        _ entry: ParmaEntry,
        venue: VenueCandidate,
        rating: RatingSnapshot,
        notes: AttributedString,
        photoFilename: String?,
        deliberateRerating: Bool,
        in context: ModelContext
    ) throws {
        guard rating.hasValidScores else { throw EntryRepositoryError.invalidRating }
        let ratingChanged = !entry.currentRating.numericallyMatches(rating)
        if ratingChanged || deliberateRerating {
            let revision = RatingRevision(timestamp: entry.currentRatingDate, rating: entry.currentRating, entry: entry)
            context.insert(revision)
            entry.revisions.append(revision)
            entry.currentRatingDate = .now
            entry.currentRating = rating
        }

        entry.mapItemIdentifier = venue.mapItemIdentifier ?? entry.mapItemIdentifier
        entry.venueIdentity = VenueIdentity.key(for: venue)
        entry.venueName = venue.name
        entry.formattedAddress = venue.formattedAddress
        entry.latitude = venue.latitude
        entry.longitude = venue.longitude
        entry.notes = notes
        entry.photoFilename = photoFilename
        entry.lastModifiedAt = .now
        try context.save()
    }

    static func delete(_ entry: ParmaEntry, photoStore: PhotoStore, in context: ModelContext) throws {
        if let filename = entry.photoFilename {
            try? photoStore.delete(filename: filename)
        }
        context.delete(entry)
        try context.save()
    }

    static func reset(photoStore: PhotoStore, in context: ModelContext) throws {
        let entries = try context.fetch(FetchDescriptor<ParmaEntry>())
        for entry in entries {
            context.delete(entry)
        }
        try context.save()
        try photoStore.removeAll()
    }
}

enum EntryRepositoryError: Error {
    case invalidRating
}

enum EntrySortField: String, CaseIterable, Identifiable {
    case rating = "Rating"
    case alphabetical = "Alphabetical"
    case dateAdded = "Date Added"

    var id: String { rawValue }
}

enum SortDirection: String, CaseIterable, Identifiable {
    case ascending = "Ascending"
    case descending = "Descending"

    var id: String { rawValue }
}

enum EntrySorter {
    static func sorted(_ entries: [ParmaEntry], by field: EntrySortField, direction: SortDirection) -> [ParmaEntry] {
        entries.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch field {
            case .rating:
                if lhs.currentRating.normalisedScore == rhs.currentRating.normalisedScore {
                    comparison = lhs.venueName.localizedCaseInsensitiveCompare(rhs.venueName)
                } else {
                    comparison = lhs.currentRating.normalisedScore < rhs.currentRating.normalisedScore ? .orderedAscending : .orderedDescending
                }
            case .alphabetical:
                comparison = lhs.venueName.localizedCaseInsensitiveCompare(rhs.venueName)
            case .dateAdded:
                if lhs.currentRatingDate == rhs.currentRatingDate {
                    comparison = lhs.venueName.localizedCaseInsensitiveCompare(rhs.venueName)
                } else {
                    comparison = lhs.currentRatingDate < rhs.currentRatingDate ? .orderedAscending : .orderedDescending
                }
            }
            return direction == .ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
}
