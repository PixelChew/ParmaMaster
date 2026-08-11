import CoreLocation
import Foundation
import MapKit

struct VenueCandidate: Identifiable, Hashable, Codable, Sendable {
    var mapItemIdentifier: String?
    var name: String
    var formattedAddress: String
    var latitude: Double
    var longitude: Double
    /// Suburb/town captured from Maps when available; used for Areas visited.
    var locality: String?

    var id: String { VenueIdentity.key(for: self) }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(mapItem: MKMapItem) {
        mapItemIdentifier = mapItem.identifier?.rawValue
        name = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Unnamed venue"
        formattedAddress = mapItem.address?.fullAddress.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? mapItem.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true)
            ?? "Address unavailable"
        latitude = mapItem.location.coordinate.latitude
        longitude = mapItem.location.coordinate.longitude
        locality = AreaNameResolver.preferredAreaName(from: mapItem)
            ?? AreaNameResolver.fromFormattedAddress(formattedAddress)
    }

    init(
        mapItemIdentifier: String?,
        name: String,
        formattedAddress: String,
        latitude: Double,
        longitude: Double,
        locality: String? = nil
    ) {
        self.mapItemIdentifier = mapItemIdentifier
        self.name = name
        self.formattedAddress = formattedAddress
        self.latitude = latitude
        self.longitude = longitude
        self.locality = locality ?? AreaNameResolver.fromFormattedAddress(formattedAddress)
    }
}

enum VenueIdentity {
    static func key(for venue: VenueCandidate) -> String {
        if let mapItemIdentifier = venue.mapItemIdentifier, !mapItemIdentifier.isEmpty {
            return "map:\(mapItemIdentifier)"
        }
        return fallbackKey(for: venue)
    }

    /// The identity a venue would have without a Maps identifier. Exposed so
    /// indexed lookups can match a map-identified candidate against a venue
    /// that was stored before its Maps identifier was known.
    static func fallbackKey(for venue: VenueCandidate) -> String {
        let roundedLatitude = (venue.latitude * 1_000).rounded() / 1_000
        let roundedLongitude = (venue.longitude * 1_000).rounded() / 1_000
        return "fallback:\(normalise(venue.name))|\(normalise(venue.formattedAddress))|\(roundedLatitude)|\(roundedLongitude)"
    }

    static func matches(_ candidate: VenueCandidate, venue: Venue) -> Bool {
        if let candidateID = candidate.mapItemIdentifier,
           let venueID = venue.mapItemIdentifier,
           candidateID == venueID {
            return true
        }

        let sameName = normalise(candidate.name) == normalise(venue.name)
        let sameAddress = normalise(candidate.formattedAddress) == normalise(venue.formattedAddress)
        guard sameName, sameAddress || venue.formattedAddress == "Address unavailable" else { return false }

        let candidateLocation = CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
        let venueLocation = CLLocation(latitude: venue.latitude, longitude: venue.longitude)
        return candidateLocation.distance(from: venueLocation) <= 100
    }

    static func matches(_ venue: VenueCandidate, entry: ParmaEntry) -> Bool {
        guard let storedVenue = entry.venue else { return false }
        return matches(venue, venue: storedVenue)
    }

    static func normalise(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
