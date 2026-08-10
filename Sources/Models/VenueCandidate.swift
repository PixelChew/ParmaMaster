import CoreLocation
import Foundation
import MapKit

struct VenueCandidate: Identifiable, Hashable, Codable, Sendable {
    var mapItemIdentifier: String?
    var name: String
    var formattedAddress: String
    var latitude: Double
    var longitude: Double

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
    }

    init(mapItemIdentifier: String?, name: String, formattedAddress: String, latitude: Double, longitude: Double) {
        self.mapItemIdentifier = mapItemIdentifier
        self.name = name
        self.formattedAddress = formattedAddress
        self.latitude = latitude
        self.longitude = longitude
    }
}

enum VenueIdentity {
    static func key(for venue: VenueCandidate) -> String {
        if let mapItemIdentifier = venue.mapItemIdentifier, !mapItemIdentifier.isEmpty {
            return "map:\(mapItemIdentifier)"
        }

        let roundedLatitude = (venue.latitude * 1_000).rounded() / 1_000
        let roundedLongitude = (venue.longitude * 1_000).rounded() / 1_000
        return "fallback:\(normalise(venue.name))|\(normalise(venue.formattedAddress))|\(roundedLatitude)|\(roundedLongitude)"
    }

    static func matches(_ venue: VenueCandidate, entry: ParmaEntry) -> Bool {
        if let candidateID = venue.mapItemIdentifier,
           let entryID = entry.mapItemIdentifier,
           candidateID == entryID {
            return true
        }

        let sameName = normalise(venue.name) == normalise(entry.venueName)
        let sameAddress = normalise(venue.formattedAddress) == normalise(entry.formattedAddress)
        guard sameName, sameAddress || entry.formattedAddress == "Address unavailable" else { return false }

        let candidateLocation = CLLocation(latitude: venue.latitude, longitude: venue.longitude)
        let entryLocation = CLLocation(latitude: entry.latitude, longitude: entry.longitude)
        return candidateLocation.distance(from: entryLocation) <= 100
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
