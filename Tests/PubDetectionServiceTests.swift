import CoreLocation
import MapKit
import SwiftData
import UserNotifications
import XCTest
@testable import ParmaMaster

/// Base coordinate every test dwells around. 0.001 degrees of latitude is
/// roughly 111 m, so 0.00018 is about 20 m and 0.0027 is about 300 m.
private let baseLatitude = -37.81
private let baseLongitude = 144.96

@MainActor
final class PubDetectionServiceTests: XCTestCase {
    // MARK: - Dwell gating

    func testStationaryDwellSearchesOnlyAfterDwellDurationElapses() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        harness.mapSearch.results = [pubCandidate(named: "Dwell Hotel")]

        await harness.service.process(location: harness.userLocation())
        XCTAssertEqual(harness.mapSearch.searchCount, 0)

        harness.clock.advance(by: TimeInterval(harness.settings.locationReminderDelayMinutes * 60) + 30)
        await harness.service.process(location: harness.userLocation())

        XCTAssertEqual(harness.mapSearch.searchCount, 1)
        XCTAssertEqual(harness.service.currentCandidate?.name, "Dwell Hotel")
    }

    func testTransitSpeedResetsDwellSoNoSearchHappens() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        harness.mapSearch.results = [pubCandidate(named: "Transit Hotel")]

        await harness.service.process(location: harness.userLocation(speed: 3.0))
        harness.clock.advance(by: 9 * 60)
        await harness.service.process(location: harness.userLocation(speed: 3.0))

        XCTAssertEqual(harness.mapSearch.searchCount, 0)
        XCTAssertNil(harness.service.currentCandidate)
    }

    func testForegroundCheckIdentifiesTheVenueWithoutSurfacingThePrompt() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        harness.mapSearch.results = [pubCandidate(named: "Foreground Hotel")]

        await harness.service.process(location: harness.userLocation(), foregroundCheck: true)

        XCTAssertEqual(harness.mapSearch.searchCount, 1)
        XCTAssertNil(harness.service.currentCandidate)
        XCTAssertEqual(harness.notifier.scheduled.count, 1)
        XCTAssertEqual(harness.notifier.scheduled.first?.delay, harness.reminderDelay)
    }

    func testConfiguredDwellDurationDelaysTheHomeCardAndReminder() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        harness.settings.locationReminderDelayMinutes = 10
        harness.mapSearch.results = [pubCandidate(named: "Delay Hotel")]

        await harness.service.process(location: harness.userLocation(), foregroundCheck: true)
        XCTAssertNil(harness.service.currentCandidate)
        XCTAssertEqual(harness.notifier.scheduled.count, 1)
        XCTAssertEqual(harness.notifier.scheduled.first?.delay, 10 * 60)

        harness.clock.advance(by: 10 * 60 + 1)
        await harness.service.process(location: harness.userLocation())

        XCTAssertEqual(harness.service.currentCandidate?.name, "Delay Hotel")
        XCTAssertEqual(harness.notifier.scheduled.count, 1)
    }

    // MARK: - Search throttle

    func testSearchThrottleBlocksRepeatSearchesUntilItExpires() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        harness.mapSearch.results = []

        await harness.service.process(location: harness.userLocation(), foregroundCheck: true)
        XCTAssertEqual(harness.mapSearch.searchCount, 1)

        harness.clock.advance(by: 5 * 60)
        await harness.service.process(location: harness.userLocation(), foregroundCheck: true)
        XCTAssertEqual(harness.mapSearch.searchCount, 1)

        harness.clock.advance(by: 11 * 60)
        await harness.service.process(location: harness.userLocation(), foregroundCheck: true)
        XCTAssertEqual(harness.mapSearch.searchCount, 2)
    }

    // MARK: - Classification

    func testAmbiguousNearbyVenuesSurfaceChoicesWithoutANotification() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        harness.mapSearch.results = [
            pubCandidate(named: "Front Bar"),
            pubCandidate(named: "Back Bar", latitudeOffset: 0.00009)
        ]

        await harness.service.process(location: harness.userLocation(), foregroundCheck: true)

        XCTAssertEqual(harness.service.nearbyChoices.count, 2)
        XCTAssertNil(harness.service.currentCandidate)
        XCTAssertTrue(harness.notifier.scheduled.isEmpty)
    }

    func testSettledVisitSuppressesReSearchAfterTheThrottleExpires() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        harness.mapSearch.results = [pubCandidate(named: "Settled Hotel")]

        await harness.service.process(location: harness.userLocation())
        harness.clock.advance(by: TimeInterval(harness.settings.locationReminderDelayMinutes * 60) + 30)
        await harness.service.process(location: harness.userLocation())
        XCTAssertEqual(harness.mapSearch.searchCount, 1)
        XCTAssertEqual(harness.notifier.scheduled.count, 1)

        harness.clock.advance(by: 20 * 60)
        await harness.service.process(location: harness.userLocation())

        XCTAssertEqual(harness.mapSearch.searchCount, 1)
        XCTAssertEqual(harness.notifier.scheduled.count, 1)
        XCTAssertNotNil(harness.service.currentCandidate)
    }

    // MARK: - Departure

    func testSustainedDepartureClearsTheVisitSession() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        harness.mapSearch.results = [pubCandidate(named: "Departure Hotel")]

        await harness.service.process(location: harness.userLocation(), foregroundCheck: true)
        harness.clock.advance(by: harness.reminderDelay + 1)
        await harness.service.process(location: harness.userLocation())
        XCTAssertNotNil(harness.service.currentCandidate)

        harness.clock.advance(by: 60)
        await harness.service.process(location: harness.userLocation(latitudeOffset: 0.0027))
        XCTAssertNotNil(harness.service.currentCandidate)

        harness.clock.advance(by: DetectionTuning.departureDuration + 30)
        await harness.service.process(location: harness.userLocation(latitudeOffset: 0.0027))

        XCTAssertNil(harness.service.currentCandidate)
    }

    // MARK: - Persistence across relaunch

    func testRelaunchRestoresTheSessionWithoutReSearchOrDuplicateNotification() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        harness.mapSearch.results = [pubCandidate(named: "Relaunch Hotel")]

        await harness.service.process(location: harness.userLocation(), foregroundCheck: true)
        XCTAssertEqual(harness.mapSearch.searchCount, 1)
        XCTAssertEqual(harness.notifier.scheduled.count, 1)
        XCTAssertNil(harness.service.currentCandidate)

        harness.clock.advance(by: harness.reminderDelay + 1)
        await harness.service.process(location: harness.userLocation())
        XCTAssertEqual(harness.service.currentCandidate?.name, "Relaunch Hotel")

        let relaunched = harness.makeRelaunchedService()
        await relaunched.processVisit(
            coordinate: CLLocationCoordinate2D(latitude: baseLatitude, longitude: baseLongitude),
            isArrival: true
        )

        XCTAssertEqual(relaunched.currentCandidate?.name, "Relaunch Hotel")
        XCTAssertEqual(harness.mapSearch.searchCount, 1)
        XCTAssertEqual(harness.notifier.scheduled.count, 1)
    }

    func testVenueNotificationCooldownPreventsARepeatNotification() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        harness.mapSearch.results = [pubCandidate(named: "Cooldown Hotel")]

        await harness.service.process(location: harness.userLocation(), foregroundCheck: true)
        harness.clock.advance(by: harness.reminderDelay + 1)
        await harness.service.process(location: harness.userLocation())
        XCTAssertEqual(harness.mapSearch.searchCount, 1)
        XCTAssertEqual(harness.notifier.scheduled.count, 1)

        harness.service.clearVisitState()
        harness.clock.advance(by: 60 * 60)

        await harness.service.process(location: harness.userLocation())
        harness.clock.advance(by: harness.reminderDelay + 30)
        await harness.service.process(location: harness.userLocation())

        XCTAssertEqual(harness.mapSearch.searchCount, 2)
        XCTAssertNotNil(harness.service.currentCandidate)
        XCTAssertEqual(harness.notifier.scheduled.count, 1)
    }

    // MARK: - Known venues

    func testKnownVenueArrivalNotifiesWithTheExistingEntryWithoutSearching() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let candidate = pubCandidate(named: "Known Hotel", identifier: "map-known-hotel")
        let entry = try harness.repository.create(
            venue: candidate,
            rating: makeRating(parma: 4, chips: 2, salad: 2),
            notes: AttributedString(),
            photoFilename: nil,
            in: harness.context
        )
        let venueID = try XCTUnwrap(entry.venue).id

        await harness.service.processKnownVenueArrival(venueID: venueID)

        XCTAssertNil(harness.service.currentCandidate)
        XCTAssertEqual(harness.notifier.scheduled.count, 1)
        XCTAssertEqual(harness.notifier.scheduled.first?.delay, harness.reminderDelay)
        XCTAssertNotNil(harness.notifier.scheduled.first?.existing)
        XCTAssertEqual(harness.mapSearch.searchCount, 0)

        harness.clock.advance(by: harness.reminderDelay + 1)
        await harness.service.process(location: harness.userLocation())

        XCTAssertEqual(harness.service.currentCandidate?.name, "Known Hotel")
        XCTAssertEqual(harness.notifier.scheduled.count, 1)
    }

    // MARK: - Skipping

    func testSkippedVisitStaysSuppressedAfterTheThrottleExpires() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        harness.mapSearch.results = [pubCandidate(named: "Skip Hotel")]

        await harness.service.process(location: harness.userLocation(), foregroundCheck: true)
        let scheduledVenueID = try XCTUnwrap(harness.notifier.scheduled.first?.venue.id)
        XCTAssertNil(harness.service.currentCandidate)
        XCTAssertEqual(harness.notifier.scheduled.count, 1)

        harness.service.skipCurrentVisit()
        XCTAssertNil(harness.service.currentCandidate)
        XCTAssertEqual(harness.notifier.cancelled, [scheduledVenueID])

        harness.clock.advance(by: DetectionTuning.searchThrottle + 60)
        await harness.service.process(location: harness.userLocation())

        XCTAssertNil(harness.service.currentCandidate)
        XCTAssertEqual(harness.mapSearch.searchCount, 1)
        XCTAssertEqual(harness.notifier.scheduled.count, 1)
    }

    func testVisitArrivalWaitsForTheRemainingConfiguredDelay() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        harness.mapSearch.results = [pubCandidate(named: "Visit Hotel")]

        let arrival = harness.clock.date.addingTimeInterval(-10 * 60)
        await harness.service.processVisit(
            coordinate: CLLocationCoordinate2D(latitude: baseLatitude, longitude: baseLongitude),
            isArrival: true,
            arrivalDate: arrival
        )

        XCTAssertEqual(harness.mapSearch.searchCount, 1)
        XCTAssertNil(harness.service.currentCandidate)
        XCTAssertEqual(harness.notifier.scheduled.count, 1)
        XCTAssertEqual(harness.notifier.scheduled.first?.delay, 20 * 60)
    }

    func testVisitArrivalSurfacesImmediatelyWhenTheDelayHasAlreadyElapsed() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        harness.mapSearch.results = [pubCandidate(named: "Late Visit Hotel")]

        let arrival = harness.clock.date.addingTimeInterval(-harness.reminderDelay - 60)
        await harness.service.processVisit(
            coordinate: CLLocationCoordinate2D(latitude: baseLatitude, longitude: baseLongitude),
            isArrival: true,
            arrivalDate: arrival
        )

        XCTAssertEqual(harness.service.currentCandidate?.name, "Late Visit Hotel")
        XCTAssertEqual(harness.notifier.scheduled.count, 1)
        XCTAssertEqual(harness.notifier.scheduled.first?.delay, 0)
    }

    func testDepartureCancelsAPendingReminder() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        harness.mapSearch.results = [pubCandidate(named: "Cancel Hotel")]

        await harness.service.process(location: harness.userLocation(), foregroundCheck: true)
        let scheduledVenueID = try XCTUnwrap(harness.notifier.scheduled.first?.venue.id)
        XCTAssertEqual(harness.notifier.scheduled.count, 1)

        await harness.service.processVisit(
            coordinate: CLLocationCoordinate2D(latitude: baseLatitude, longitude: baseLongitude),
            isArrival: false
        )

        XCTAssertNil(harness.service.currentCandidate)
        XCTAssertEqual(harness.notifier.cancelled, [scheduledVenueID])
    }

    func testRemindersDisabledDoesNotScheduleANotification() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        harness.settings.locationRemindersEnabled = false
        harness.mapSearch.results = [pubCandidate(named: "Silent Hotel")]

        await harness.service.process(location: harness.userLocation(), foregroundCheck: true)
        harness.clock.advance(by: harness.reminderDelay + 1)
        await harness.service.process(location: harness.userLocation())

        XCTAssertEqual(harness.service.currentCandidate?.name, "Silent Hotel")
        XCTAssertTrue(harness.notifier.scheduled.isEmpty)
    }

    // MARK: - Helpers

    private func makeHarness() throws -> DetectionHarness {
        try DetectionHarness()
    }

    private func pubCandidate(
        named name: String,
        identifier: String? = nil,
        latitudeOffset: Double = 0
    ) -> VenueCandidate {
        VenueCandidate(
            mapItemIdentifier: identifier,
            name: name,
            formattedAddress: "1 Test Street, Melbourne VIC",
            latitude: baseLatitude + latitudeOffset,
            longitude: baseLongitude
        )
    }

    private func makeRating(parma: Decimal, chips: Decimal, salad: Decimal) -> RatingSnapshot {
        RatingSnapshot(
            components: [
                ComponentRatingSnapshot(category: .parma, isEnabled: true, displayMode: .numeric, maximum: 5, score: parma),
                ComponentRatingSnapshot(category: .chips, isEnabled: true, displayMode: .numeric, maximum: 3, score: chips),
                ComponentRatingSnapshot(category: .salad, isEnabled: true, displayMode: .numeric, maximum: 2, score: salad)
            ],
            overallDisplayMode: .numeric
        )
    }
}

// MARK: - Test doubles

@MainActor
private final class MockMapSearch: MapSearching {
    var results: [VenueCandidate] = []
    private(set) var searchCount = 0

    func resolve(_ completion: MKLocalSearchCompletion) async throws -> VenueCandidate {
        guard let first = results.first else { throw MapSearchError.noResults }
        return first
    }

    func nearbyPubCandidates(around location: CLLocation) async throws -> [VenueCandidate] {
        searchCount += 1
        return results
    }
}

@MainActor
private final class MockNotifier: VisitNotifying {
    var authorizationStatus: UNAuthorizationStatus = .authorized
    private(set) var scheduled: [(venue: VenueCandidate, existing: ParmaEntry?, delay: TimeInterval)] = []
    private(set) var cancelled: [String] = []

    func scheduleVisitReminder(venue: VenueCandidate, existingEntry: ParmaEntry?, after delay: TimeInterval) async throws {
        scheduled.append((venue: venue, existing: existingEntry, delay: delay))
    }

    func cancelVisitReminder(forVenueID venueID: String) {
        cancelled.append(venueID)
    }
}

/// Mutable reference clock captured by `PubDetectionService.now`.
private final class TestClock {
    var date: Date

    init(date: Date) {
        self.date = date
    }

    func advance(by interval: TimeInterval) {
        date = date.addingTimeInterval(interval)
    }
}

/// A fully wired detection service over fresh in-memory storage, a fresh
/// UserDefaults suite, a controllable clock and mock collaborators.
@MainActor
private final class DetectionHarness {
    let service: PubDetectionService
    let mapSearch: MockMapSearch
    let notifier: MockNotifier
    let clock: TestClock
    let context: ModelContext
    let repository: LocalParmaRepository
    let settings: AppSettings
    let defaults: UserDefaults

    private let container: ModelContainer
    private let settingsDefaults: UserDefaults
    private let suiteName: String
    private let settingsSuiteName: String

    init() throws {
        let suiteName = "PubDetectionTests-\(UUID().uuidString)"
        let settingsSuiteName = "PubDetectionTestsSettings-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settingsDefaults = try XCTUnwrap(UserDefaults(suiteName: settingsSuiteName))

        let settings = AppSettings(defaults: settingsDefaults)
        settings.locationUseEnabled = true
        settings.locationRemindersEnabled = true

        let container = try ModelContainer(
            for: Venue.self, ParmaEntry.self, RatingRevision.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let repository = LocalParmaRepository()
        let mapSearch = MockMapSearch()
        let notifier = MockNotifier()
        let clock = TestClock(date: Date(timeIntervalSince1970: 1_755_000_000))

        let service = PubDetectionService(mapSearch: mapSearch, notificationService: notifier, defaults: defaults)
        service.configure(context: context, settings: settings, repository: repository, locationService: nil)
        service.now = { clock.date }

        self.suiteName = suiteName
        self.settingsSuiteName = settingsSuiteName
        self.defaults = defaults
        self.settingsDefaults = settingsDefaults
        self.settings = settings
        self.container = container
        self.context = context
        self.repository = repository
        self.mapSearch = mapSearch
        self.notifier = notifier
        self.clock = clock
        self.service = service
    }

    var reminderDelay: TimeInterval {
        TimeInterval(settings.locationReminderDelayMinutes * 60)
    }

    /// Simulates an app relaunch: a second service over the same defaults
    /// suite, so persisted visit state is read back from disk.
    func makeRelaunchedService() -> PubDetectionService {
        let relaunched = PubDetectionService(mapSearch: mapSearch, notificationService: notifier, defaults: defaults)
        relaunched.configure(context: context, settings: settings, repository: repository, locationService: nil)
        let clock = clock
        relaunched.now = { clock.date }
        return relaunched
    }

    func userLocation(latitudeOffset: Double = 0, speed: CLLocationSpeed = 0) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: baseLatitude + latitudeOffset,
                longitude: baseLongitude
            ),
            altitude: 10,
            horizontalAccuracy: 20,
            verticalAccuracy: 10,
            course: 0,
            speed: speed,
            timestamp: clock.date
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
    }
}
