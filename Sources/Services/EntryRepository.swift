import CoreLocation
import Foundation
import Observation
import SwiftData

@MainActor
protocol ParmaRepositoryProtocol: AnyObject {
    func findExisting(for venue: VenueCandidate, in entries: [ParmaEntry]) -> ParmaEntry?
    func findExisting(for venue: VenueCandidate, in context: ModelContext) throws -> ParmaEntry?
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

    /// Indexed lookup replacing the previous full-table linear scan. Both
    /// `venueIdentity` and `id` are unique attributes, so the store answers
    /// these predicates without materialising the table.
    func findExisting(for venue: VenueCandidate, in context: ModelContext) throws -> ParmaEntry? {
        guard let matched = try findVenue(matching: venue, in: context) else { return nil }
        return matched.entries.max { $0.lastModifiedAt < $1.lastModifiedAt }
    }

    private func findVenue(matching candidate: VenueCandidate, in context: ModelContext) throws -> Venue? {
        let primaryKey = VenueIdentity.key(for: candidate)
        let fallbackKey = VenueIdentity.fallbackKey(for: candidate)
        let predicate: Predicate<Venue>
        if let mapItemIdentifier = candidate.mapItemIdentifier, !mapItemIdentifier.isEmpty {
            predicate = #Predicate { venue in
                venue.venueIdentity == primaryKey
                    || venue.venueIdentity == fallbackKey
                    || venue.mapItemIdentifier == mapItemIdentifier
            }
        } else {
            predicate = #Predicate { venue in
                venue.venueIdentity == primaryKey || venue.venueIdentity == fallbackKey
            }
        }
        let candidates = try context.fetch(FetchDescriptor<Venue>(predicate: predicate))
        // An exact identity-key hit is authoritative even when the looser
        // name/address/proximity verification fails (e.g. a venue renamed in
        // Maps); anything else that fails verification is not a match.
        return candidates.first { VenueIdentity.matches(candidate, venue: $0) }
            ?? candidates.first { $0.venueIdentity == primaryKey }
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
        if let existing = try findExisting(for: candidate, in: context) { return existing }

        let venue: Venue
        if let existingVenue = try findVenue(matching: candidate, in: context) {
            venue = existingVenue
            AreaResolutionService.applyImmediateLocality(
                to: venue,
                candidateLocality: candidate.locality,
                formattedAddress: candidate.formattedAddress
            )
        } else {
            venue = Venue(
                mapItemIdentifier: candidate.mapItemIdentifier,
                venueIdentity: VenueIdentity.key(for: candidate),
                name: candidate.name,
                formattedAddress: candidate.formattedAddress,
                latitude: candidate.latitude,
                longitude: candidate.longitude,
                locality: AreaNameResolver.cleaned(candidate.locality)
                    ?? AreaNameResolver.fromFormattedAddress(candidate.formattedAddress)
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
        if let currentVenue {
            AreaResolutionService.applyImmediateLocality(
                to: currentVenue,
                candidateLocality: candidate.locality,
                formattedAddress: candidate.formattedAddress
            )
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
        // Batch deletes (`context.delete(model:)`) trip the mandatory inverse
        // between `Venue.entries` and `ParmaEntry.venue`, so reset removes
        // objects individually: entries first (cascading revisions), venues after.
        let entries = try context.fetch(FetchDescriptor<ParmaEntry>())
        for entry in entries { context.delete(entry) }
        try context.save()
        let venues = try context.fetch(FetchDescriptor<Venue>())
        for venue in venues { context.delete(venue) }
        try context.save()
        try photoStore.removeAll()
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
