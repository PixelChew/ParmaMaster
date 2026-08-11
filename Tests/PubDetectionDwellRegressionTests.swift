import CoreLocation
import MapKit
import SwiftData
import UserNotifications
import XCTest
@testable import ParmaMaster

private let regressionLatitude = -37.81
private let regressionLongitude = 144.96

@MainActor
final class PubDetectionDwellRegressionTests: XCTestCase {
    func testPendingDwellCancelsWhenUserLeavesVenueAreaBeforeActivation() async throws {
        let harness = try RegressionDetectionHarness()
        defer { harness.cleanUp() }
        harness.mapSearch.results = [candidate(named: "Pass By Hotel")]

        await harness.service.process(location: harness.userLocation(), foregroundCheck: true)

        XCTAssertNil(harness.service.currentCandidate)
        XCTAssertEqual(harness.notifier.scheduled.count, 1)

        harness.clock.advance(by: 60)
        await harness.service.process(location: harness.userLocation(latitudeOffset: 0.0018))

        XCTAssertNil(harness.service.currentCandidate)
        XCTAssertEqual(harness.notifier.cancelledVenueIDs.count, 1)
    }

    func testKnownVenueRerunOptOutSuppressesLocationSuggestion() async throws {
        let harness = try RegressionDetectionHarness()
        defer { harness.cleanUp() }
        let venueCandidate = candidate(named: "Opt Out Hotel", identifier: "map-opt-out-known")
        let entry = try harness.repository.create(
            venue: venueCandidate,
            rating: rating(),
            notes: AttributedString(),
            photoFilename: nil,
            in: harness.context
        )
        let venue = try XCTUnwrap(entry.venue)
        venue.excludedFromRerun = true
        try harness.context.save()

        await harness.service.processKnownVenueArrival(venueID: venue.id)

        XCTAssertNil(harness.service.currentCandidate)
        XCTAssertTrue(harness.notifier.scheduled.isEmpty)
    }

    func testNearbyExistingVenueRerunOptOutSuppressesLocationSuggestion() async throws {
        let harness = try RegressionDetectionHarness()
        defer { harness.cleanUp() }
        let venueCandidate = candidate(named: "Nearby Opt Out", identifier: "map-opt-out-nearby")
        let entry = try harness.repository.create(
            venue: venueCandidate,
            rating: rating(),
            notes: AttributedString(),
            photoFilename: nil,
            in: harness.context
        )
        let venue = try XCTUnwrap(entry.venue)
        venue.excludedFromRerun = true
        try harness.context.save()
        harness.mapSearch.results = [venueCandidate]

        await harness.service.process(location: harness.userLocation(), foregroundCheck: true)

        XCTAssertNil(harness.service.currentCandidate)
        XCTAssertTrue(harness.notifier.scheduled.isEmpty)
    }

    private func candidate(named name: String, identifier: String? = nil) -> VenueCandidate {
        VenueCandidate(
            mapItemIdentifier: identifier,
            name: name,
            formattedAddress: "1 Test Street, Melbourne VIC",
            latitude: regressionLatitude,
            longitude: regressionLongitude
        )
    }

    private func rating() -> RatingSnapshot {
        RatingSnapshot(
            components: [
                ComponentRatingSnapshot(category: .parma, isEnabled: true, displayMode: .numeric, maximum: 5, score: 4),
                ComponentRatingSnapshot(category: .chips, isEnabled: true, displayMode: .numeric, maximum: 3, score: 2),
                ComponentRatingSnapshot(category: .salad, isEnabled: true, displayMode: .numeric, maximum: 2, score: 2)
            ],
            overallDisplayMode: .numeric
        )
    }
}

@MainActor
private final class RegressionMapSearch: MapSearching {
    var results: [VenueCandidate] = []

    func resolve(_ completion: MKLocalSearchCompletion) async throws -> VenueCandidate {
        guard let first = results.first else { throw MapSearchError.noResults }
        return first
    }

    func nearbyPubCandidates(around location: CLLocation) async throws -> [VenueCandidate] {
        results
    }
}

@MainActor
private final class RegressionNotifier: VisitNotifying {
    var authorizationStatus: UNAuthorizationStatus = .authorized
    private(set) var scheduled: [(venue: VenueCandidate, existing: ParmaEntry?, delay: TimeInterval)] = []
    private(set) var cancelledVenueIDs: [String] = []

    func scheduleVisitReminder(
        venue: VenueCandidate,
        existingEntry: ParmaEntry?,
        delay: TimeInterval
    ) async throws {
        scheduled.append((venue: venue, existing: existingEntry, delay: delay))
    }

    func cancelVisitReminder(venueID: String) {
        cancelledVenueIDs.append(venueID)
    }
}

private final class RegressionClock {
    var date = Date(timeIntervalSince1970: 1_755_000_000)

    func advance(by interval: TimeInterval) {
        date = date.addingTimeInterval(interval)
    }
}

@MainActor
private final class RegressionDetectionHarness {
    let service: PubDetectionService
    let mapSearch: RegressionMapSearch
    let notifier: RegressionNotifier
    let clock: RegressionClock
    let context: ModelContext
    let repository: LocalParmaRepository
    let settings: AppSettings

    private let defaults: UserDefaults
    private let settingsDefaults: UserDefaults
    private let suiteName: String
    private let settingsSuiteName: String
    private let container: ModelContainer

    init() throws {
        suiteName = "PubDetectionDwellRegression-\(UUID().uuidString)"
        settingsSuiteName = "PubDetectionDwellRegressionSettings-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        settingsDefaults = try XCTUnwrap(UserDefaults(suiteName: settingsSuiteName))

        settings = AppSettings(defaults: settingsDefaults)
        settings.locationUseEnabled = true
        settings.locationRemindersEnabled = true

        container = try ModelContainer(
            for: Venue.self, ParmaEntry.self, RatingRevision.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        repository = LocalParmaRepository()
        mapSearch = RegressionMapSearch()
        notifier = RegressionNotifier()
        clock = RegressionClock()

        service = PubDetectionService(mapSearch: mapSearch, notificationService: notifier, defaults: defaults)
        service.configure(context: context, settings: settings, repository: repository, locationService: nil)
        let clock = clock
        service.now = { clock.date }
    }

    func userLocation(latitudeOffset: Double = 0) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: regressionLatitude + latitudeOffset,
                longitude: regressionLongitude
            ),
            altitude: 10,
            horizontalAccuracy: 20,
            verticalAccuracy: 10,
            course: 0,
            speed: 0,
            timestamp: clock.date
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
    }
}
