import CoreLocation
import Foundation
import MapKit

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
        for query in ["pub", "brewery", "nightlife"] {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 450,
                longitudinalMeters: 450
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

@MainActor
final class MapSearchCompleter: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet { completer.queryFragment = query }
    }
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    @Published private(set) var errorMessage: String?

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
        completer.pointOfInterestFilter = MKPointOfInterestFilter(including: [.nightlife, .brewery, .restaurant])
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
