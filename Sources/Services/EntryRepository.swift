import CoreLocation
import Foundation
import Observation
import SwiftData

@MainActor
protocol ParmaRepositoryProtocol: AnyObject {
    func findExisting(for venue: VenueCandidate, in entries: [ParmaEntry]) -> ParmaEntry?
    func create(venue: VenueCandidate, rating: RatingSnapshot, notes: AttributedString, photoFilename: String?, in context: ModelContext) throws -> ParmaEntry
    func update(_ entry: ParmaEntry, venue: VenueCandidate, rating: RatingSnapshot, notes: AttributedString, photoFilename: String?, deliberateRerating: Bool, in context: ModelContext) throws
    func delete(_ entry: ParmaEntry, photoStore: PhotoStore, in context: ModelContext) throws
    func reset(photoStore: PhotoStore, in context: ModelContext) throws
}

@MainActor
@Observable
final class LocalParmaRepository: ParmaRepositoryProtocol {
    func findExisting(for venue: VenueCandidate, in entries: [ParmaEntry]) -> ParmaEntry? {
        entries.first { VenueIdentity.matches(venue, entry: $0) }
    }

    @discardableResult
    func create(
        venue candidate: VenueCandidate,
        rating: RatingSnapshot,
        notes: AttributedString,
        photoFilename: String?,
        in context: ModelContext
    ) throws -> ParmaEntry {
        guard rating.hasValidScores else { throw EntryRepositoryError.invalidRating }
        let entries = try context.fetch(FetchDescriptor<ParmaEntry>())
        if let existing = findExisting(for: candidate, in: entries) { return existing }

        let venues = try context.fetch(FetchDescriptor<Venue>())
        let venue: Venue
        if let existingVenue = venues.first(where: { VenueIdentity.matches(candidate, venue: $0) }) {
            venue = existingVenue
        } else {
            venue = Venue(
                mapItemIdentifier: candidate.mapItemIdentifier,
                venueIdentity: VenueIdentity.key(for: candidate),
                name: candidate.name,
                formattedAddress: candidate.formattedAddress,
                latitude: candidate.latitude,
                longitude: candidate.longitude
            )
            context.insert(venue)
        }

        let entry = ParmaEntry(
            venue: venue,
            rating: rating,
            notes: notes,
            photoFilename: photoFilename
        )
        context.insert(entry)
        try context.save()
        AreaResolutionService.scheduleResolveIfNeeded(venue, in: context)
        return entry
    }

    func update(
        _ entry: ParmaEntry,
        venue candidate: VenueCandidate,
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

        let currentVenue = entry.venue
        let coordinatesChanged =
            currentVenue?.latitude != candidate.latitude
            || currentVenue?.longitude != candidate.longitude
        currentVenue?.mapItemIdentifier = candidate.mapItemIdentifier ?? currentVenue?.mapItemIdentifier
        currentVenue?.venueIdentity = VenueIdentity.key(for: candidate)
        currentVenue?.name = candidate.name
        currentVenue?.formattedAddress = candidate.formattedAddress
        currentVenue?.latitude = candidate.latitude
        currentVenue?.longitude = candidate.longitude
        if coordinatesChanged {
            currentVenue?.locality = nil
        }
        entry.notes = notes
        entry.photoFilename = photoFilename
        entry.lastModifiedAt = .now
        try context.save()
        AreaResolutionService.scheduleResolveIfNeeded(currentVenue, in: context)
    }

    func delete(_ entry: ParmaEntry, photoStore: PhotoStore, in context: ModelContext) throws {
        if let filename = entry.photoFilename { try? photoStore.delete(filename: filename) }
        let venue = entry.venue
        context.delete(entry)
        try context.save()

        if let venue, venue.entries.isEmpty {
            context.delete(venue)
            try context.save()
        }
    }

    func reset(photoStore: PhotoStore, in context: ModelContext) throws {
        let entries = try context.fetch(FetchDescriptor<ParmaEntry>())
        for entry in entries { context.delete(entry) }
        try context.save()
        let venues = try context.fetch(FetchDescriptor<Venue>())
        for venue in venues { context.delete(venue) }
        try context.save()
        try photoStore.removeAll()
    }
}

@MainActor
enum EntryRepository {
    private static let local = LocalParmaRepository()

    static func findExisting(for venue: VenueCandidate, in entries: [ParmaEntry]) -> ParmaEntry? {
        local.findExisting(for: venue, in: entries)
    }

    static func create(venue: VenueCandidate, rating: RatingSnapshot, notes: AttributedString, photoFilename: String?, in context: ModelContext) throws -> ParmaEntry {
        try local.create(venue: venue, rating: rating, notes: notes, photoFilename: photoFilename, in: context)
    }

    static func update(_ entry: ParmaEntry, venue: VenueCandidate, rating: RatingSnapshot, notes: AttributedString, photoFilename: String?, deliberateRerating: Bool, in context: ModelContext) throws {
        try local.update(entry, venue: venue, rating: rating, notes: notes, photoFilename: photoFilename, deliberateRerating: deliberateRerating, in: context)
    }

    static func delete(_ entry: ParmaEntry, photoStore: PhotoStore, in context: ModelContext) throws {
        try local.delete(entry, photoStore: photoStore, in: context)
    }

    static func reset(photoStore: PhotoStore, in context: ModelContext) throws {
        try local.reset(photoStore: photoStore, in: context)
    }
}

enum EntryRepositoryError: Error { case invalidRating }

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
