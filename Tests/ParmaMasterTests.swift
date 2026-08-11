import CoreLocation
import SwiftData
import UIKit
import XCTest
@testable import ParmaMaster

@MainActor
final class ParmaMasterTests: XCTestCase {
    func testHomeGreetingCandidatesRespectTimeOfDay() {
        let morning = HomeGreeting.candidates(at: greetingDate(hour: 9), calendar: greetingCalendar)
        XCTAssertTrue(morning.contains("Good morning."))
        XCTAssertFalse(morning.contains("Good afternoon."))
        XCTAssertFalse(morning.contains("Good evening."))
        XCTAssertFalse(morning.contains("Parma dinner?"))

        let dinner = HomeGreeting.candidates(at: greetingDate(hour: 19), calendar: greetingCalendar)
        XCTAssertTrue(dinner.contains("Good evening."))
        XCTAssertTrue(dinner.contains("Parma dinner?"))
        XCTAssertTrue(dinner.contains("Winner winna parma dinner"))

        let lateNight = HomeGreeting.candidates(at: greetingDate(hour: 23), calendar: greetingCalendar)
        XCTAssertTrue(lateNight.contains("Late night parma?"))
        XCTAssertFalse(lateNight.contains("Up late?"))
    }

    func testHomeGreetingIncludesTheCurrentDayName() {
        let candidates = HomeGreeting.candidates(at: greetingDate(hour: 13), calendar: greetingCalendar)
        XCTAssertTrue(candidates.contains("Monday parma day."))
    }

    func testV1StoreMigratesIntoVenueAndPreservesEntryData() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ParmaMasterMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "migration.store")
        let entryID = UUID()
        let rating = makeRating(parma: 4, chips: 2, salad: 2)
        let notes = AttributedString("Migration notes")
        try createV1Store(at: storeURL, entryID: entryID, rating: rating, notes: notes)

        let schema = Schema(versionedSchema: ParmaSchemaV2.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: ParmaMigrationPlan.self, configurations: [configuration])
        let context = ModelContext(container)
        let entries = try context.fetch(FetchDescriptor<ParmaEntry>())
        let venues = try context.fetch(FetchDescriptor<Venue>())

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(venues.count, 1)
        XCTAssertEqual(entries[0].id, entryID)
        XCTAssertEqual(entries[0].venue?.id, entryID)
        XCTAssertEqual(entries[0].currentRating, rating)
        XCTAssertEqual(entries[0].notes, notes)
        XCTAssertEqual(entries[0].photoFilename, "migration.jpg")
    }

    func testLegacyBackupUpgradesToSeparatedVenuePayload() {
        let legacy = LegacyBackupPayloadV1(
            schemaVersion: 1,
            exportedAt: .now,
            settings: AppSettingsSnapshot(),
            entries: [LegacyEntryBackupV1(
                id: UUID(), venueIdentity: "map:one", mapItemIdentifier: "one",
                venueName: "Backup Hotel", formattedAddress: "1 Test Street",
                latitude: -37.81, longitude: 144.96, createdAt: .now,
                currentRatingDate: .now, lastModifiedAt: .now,
                currentRating: makeRating(parma: 4, chips: 2, salad: 2),
                notesData: Data(), photoFilename: nil, photoData: nil, revisions: []
            )]
        )

        let upgraded = legacy.upgraded()
        XCTAssertEqual(upgraded.schemaVersion, 2)
        XCTAssertEqual(upgraded.venues.count, 1)
        XCTAssertEqual(upgraded.entries.first?.venueID, upgraded.venues.first?.id)
    }

    func testCurrentUserProfilePersistsDisplayNameLocally() {
        let suiteName = "CurrentUserProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = CurrentUserProfile(defaults: defaults)
        XCTAssertEqual(profile.displayName, "Hamish")
        profile.displayName = "Test User"
        XCTAssertEqual(CurrentUserProfile(defaults: defaults).displayName, "Test User")
        XCTAssertTrue(
            HomeGreeting.candidates(
                at: greetingDate(hour: 9),
                calendar: greetingCalendar,
                displayName: profile.displayName
            ).contains("Welcome back, Test User.")
        )
    }

    func testDecimalRatingDerivesTotalAndMaximum() {
        let rating = makeRating(parma: Decimal(string: "4.5")!, chips: 2, salad: Decimal(string: "1.5")!)
        XCTAssertEqual(rating.total, 8)
        XCTAssertEqual(rating.maximum, 10)
        XCTAssertTrue(rating.hasValidScores)
    }

    func testRatingAboveComponentMaximumIsRejectedAndClampedAtInput() {
        let invalid = makeRating(parma: 6, chips: 2, salad: 2)

        XCTAssertFalse(invalid.hasValidScores)
        XCTAssertEqual(
            RatingInputPolicy.boundedText("66", maximum: 5, locale: Locale(identifier: "en_AU")),
            "5"
        )
    }

    func testStarsDisplayStyleAppliesToEveryEnabledCategory() {
        var configuration = RatingConfiguration.default

        XCTAssertTrue(configuration.applyOverallDisplayMode(.stars))
        XCTAssertEqual(configuration.overallDisplayMode, .stars)
        XCTAssertTrue(configuration.enabledComponents.allSatisfy { $0.displayMode == .stars })
        XCTAssertTrue(RatingSnapshot.blank(configuration: configuration).enabledComponents.allSatisfy { $0.displayMode == .stars })
    }

    func testLocationActivityRequiresEnabledRemindersAndAlwaysAuthorizationForBackground() {
        XCTAssertEqual(
            LocationActivityPolicy.mode(
                locationUseEnabled: true,
                remindersEnabled: false,
                authorizationStatus: .authorizedAlways,
                sceneIsActive: false
            ),
            .stopped
        )
        XCTAssertEqual(
            LocationActivityPolicy.mode(
                locationUseEnabled: true,
                remindersEnabled: true,
                authorizationStatus: .authorizedWhenInUse,
                sceneIsActive: false
            ),
            .stopped
        )
        XCTAssertEqual(
            LocationActivityPolicy.mode(
                locationUseEnabled: true,
                remindersEnabled: true,
                authorizationStatus: .authorizedAlways,
                sceneIsActive: false
            ),
            .background
        )
    }

    func testLocationActivityUsesForegroundUpdatesOnlyWhileSceneIsActive() {
        XCTAssertEqual(
            LocationActivityPolicy.mode(
                locationUseEnabled: true,
                remindersEnabled: false,
                authorizationStatus: .authorizedWhenInUse,
                sceneIsActive: true
            ),
            .foreground
        )
        XCTAssertEqual(
            LocationActivityPolicy.mode(
                locationUseEnabled: true,
                remindersEnabled: false,
                authorizationStatus: .authorizedWhenInUse,
                sceneIsActive: false
            ),
            .stopped
        )
    }

    func testRepositoryRejectsAnOverMaximumRating() throws {
        let context = try makeContext()

        XCTAssertThrowsError(
            try EntryRepository.create(
                venue: venue(name: "Invalid Rating Pub"),
                rating: makeRating(parma: 6, chips: 2, salad: 2),
                notes: AttributedString(),
                photoFilename: nil,
                in: context
            )
        )
    }

    func testRatingSortUsesNormalisedScoreInsteadOfRawTotal() {
        let eightOfTen = makeEntry(name: "Eight", rating: makeRating(parma: 4, chips: 2, salad: 2))
        let fifteenOfTwenty = makeEntry(
            name: "Fifteen",
            rating: RatingSnapshot(
                components: [
                    ComponentRatingSnapshot(category: .parma, isEnabled: true, displayMode: .numeric, maximum: 10, score: 8),
                    ComponentRatingSnapshot(category: .chips, isEnabled: true, displayMode: .numeric, maximum: 6, score: 4),
                    ComponentRatingSnapshot(category: .salad, isEnabled: true, displayMode: .numeric, maximum: 4, score: 3)
                ],
                overallDisplayMode: .numeric
            )
        )

        let sorted = EntrySorter.sorted([fifteenOfTwenty, eightOfTen], by: .rating, direction: .descending)
        XCTAssertEqual(sorted.map(\.venueName), ["Eight", "Fifteen"])
    }

    func testChangingRatingArchivesPreviousSnapshot() throws {
        let context = try makeContext()
        let entry = makeEntry(name: "The Test Pub", rating: makeRating(parma: 4, chips: 2, salad: 2))
        context.insert(entry)
        try context.save()

        try EntryRepository.update(
            entry,
            venue: venue(name: "The Test Pub"),
            rating: makeRating(parma: Decimal(string: "4.5")!, chips: 2, salad: 2),
            notes: AttributedString("Still excellent"),
            photoFilename: nil,
            deliberateRerating: false,
            in: context
        )

        XCTAssertEqual(entry.revisions.count, 1)
        XCTAssertEqual(entry.revisions.first?.rating.total, 8)
        XCTAssertEqual(entry.currentRating.total, Decimal(string: "8.5")!)
    }

    func testChangingOnlyNotesDoesNotCreateHistory() throws {
        let context = try makeContext()
        let rating = makeRating(parma: 4, chips: 2, salad: 2)
        let entry = makeEntry(name: "The Notes Pub", rating: rating)
        context.insert(entry)
        try context.save()

        try EntryRepository.update(
            entry,
            venue: venue(name: "The Notes Pub"),
            rating: rating,
            notes: AttributedString("Corrected note"),
            photoFilename: nil,
            deliberateRerating: false,
            in: context
        )

        XCTAssertTrue(entry.revisions.isEmpty)
        XCTAssertEqual(entry.searchableNotes, "Corrected note")
    }

    func testVenueIdentityPrefersMapIdentifierAndFallbackUsesProximity() {
        let candidate = VenueCandidate(
            mapItemIdentifier: "apple-maps-place-1",
            name: "The Corner Hotel",
            formattedAddress: "1 Test Street, Melbourne VIC",
            latitude: -37.81,
            longitude: 144.96
        )
        let entry = ParmaEntry(
            venueIdentity: VenueIdentity.key(for: candidate),
            mapItemIdentifier: "apple-maps-place-1",
            venueName: candidate.name,
            formattedAddress: candidate.formattedAddress,
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            rating: makeRating(parma: 4, chips: 2, salad: 2)
        )

        XCTAssertEqual(VenueIdentity.key(for: candidate), "map:apple-maps-place-1")
        XCTAssertTrue(VenueIdentity.matches(candidate, entry: entry))
    }

    func testHistoricalScaleSnapshotDoesNotFollowGlobalSettings() {
        let old = makeRating(parma: 4, chips: 2, salad: 2)
        var changed = RatingConfiguration.default
        changed.update(.parma) { $0.maximum = 10 }

        XCTAssertEqual(old.maximum, 10)
        XCTAssertEqual(changed.enabledComponents.map(\.maximum).reduce(0, +), 15)
        XCTAssertEqual(old.maximum, 10)
    }

    func testStoredPhotoResizesProportionallyWithoutDistortion() throws {
        let sourceSize = CGSize(width: 2_400, height: 1_200)
        let renderer = UIGraphicsImageRenderer(size: sourceSize)
        let source = renderer.image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(origin: .zero, size: sourceSize))
        }
        let store = PhotoStore()
        let filename = try store.save(imageData: try XCTUnwrap(source.pngData()))
        defer { try? store.delete(filename: filename) }

        let stored = try XCTUnwrap(store.image(for: filename))
        XCTAssertEqual(stored.size.width, 1_920, accuracy: 1)
        XCTAssertEqual(stored.size.height, 960, accuracy: 1)
        XCTAssertEqual(stored.size.width / stored.size.height, 2, accuracy: 0.001)
    }

    private var greetingCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_AU")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func greetingDate(hour: Int) -> Date {
        greetingCalendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: hour))!
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Venue.self, ParmaEntry.self, RatingRevision.self, configurations: configuration)
        return ModelContext(container)
    }

    private func createV1Store(at url: URL, entryID: UUID, rating: RatingSnapshot, notes: AttributedString) throws {
        let schema = Schema(versionedSchema: ParmaSchemaV1.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let revision = ParmaSchemaV1.RatingRevision(
            id: UUID(), timestamp: .now, ratingData: try JSONEncoder().encode(rating)
        )
        let entry = ParmaSchemaV1.ParmaEntry(
            id: entryID, venueIdentity: "map:migration-place", mapItemIdentifier: "migration-place",
            venueName: "Migration Hotel", formattedAddress: "1 Test Street",
            latitude: -37.81, longitude: 144.96, createdAt: .now,
            currentRatingDate: .now, lastModifiedAt: .now,
            currentRatingData: try JSONEncoder().encode(rating),
            notesData: try JSONEncoder().encode(notes), photoFilename: "migration.jpg",
            revisions: [revision]
        )
        revision.entry = entry
        context.insert(entry)
        try context.save()
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

    private func venue(name: String) -> VenueCandidate {
        VenueCandidate(
            mapItemIdentifier: "map-\(name)",
            name: name,
            formattedAddress: "1 Test Street, Melbourne VIC",
            latitude: -37.81,
            longitude: 144.96
        )
    }

    private func makeEntry(name: String, rating: RatingSnapshot) -> ParmaEntry {
        let candidate = venue(name: name)
        return ParmaEntry(
            venueIdentity: VenueIdentity.key(for: candidate),
            mapItemIdentifier: candidate.mapItemIdentifier,
            venueName: name,
            formattedAddress: candidate.formattedAddress,
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            rating: rating
        )
    }
}
