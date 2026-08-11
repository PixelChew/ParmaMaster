import CoreLocation
import Foundation
import MapKit
import Observation

@MainActor
protocol MapSearching {
    func resolve(_ completion: MKLocalSearchCompletion) async throws -> VenueCandidate
    func nearbyPubCandidates(around location: CLLocation) async throws -> [VenueCandidate]
}

@MainActor
struct MapSearchService: MapSearching {
    func resolve(_ completion: MKLocalSearchCompletion) async throws -> VenueCandidate {
        let request = MKLocalSearch.Request(completion: completion)
        let response = try await MKLocalSearch(request: request).start()
        guard let mapItem = response.mapItems.first else { throw MapSearchError.noResults }
        return VenueCandidate(mapItem: mapItem)
    }

    func nearbyPubCandidates(around location: CLLocation) async throws -> [VenueCandidate] {
        var found: [String: VenueCandidate] = [:]
        for query in DetectionTuning.searchQueries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: DetectionTuning.searchRegionSpan,
                longitudinalMeters: DetectionTuning.searchRegionSpan
            )
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.nightlife, .brewery, .restaurant])
            let response = try await MKLocalSearch(request: request).start()
            for mapItem in response.mapItems {
                let venue = VenueCandidate(mapItem: mapItem)
                found[venue.id] = venue
            }
        }
        return found.values.sorted {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: location)
                < CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: location)
        }
    }
}

enum MapSearchError: LocalizedError {
    case noResults

    var errorDescription: String? { "No matching venue was found. Check your connection and try again." }
}

@Observable
@MainActor
final class MapSearchCompleter: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
    var query = ""
    private(set) var results: [MKLocalSearchCompletion] = []
    private(set) var errorMessage: String?

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
        completer.pointOfInterestFilter = MKPointOfInterestFilter(including: [.nightlife, .brewery, .restaurant])
    }

    /// Updates the visible query and forwards it to MapKit. Bindings must
    /// go through this method because `@Observable` bypasses `didSet`; direct
    /// mutation previously left the venue search list out of sync.
    func setQuery(_ value: String) {
        guard query != value else { return }
        query = value
        completer.queryFragment = value
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
        errorMessage = nil
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
        errorMessage = "Venue search is unavailable right now. Check your connection and try again."
    }
}
