import CoreLocation
import SwiftData
import UIKit
import XCTest
@testable import ParmaMaster

@MainActor
final class ParmaMasterTests: XCTestCase {
    func testV1StoreMigratesEntryVenueNotesPhotoTimestampsAndHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ParmaMasterMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "migration.store")
        let entryID = UUID()
        let revisionID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let rating = makeRating(parma: 4, chips: 2, salad: 2)
        let notes = AttributedString("Migration notes")

        try createV1Store(
            at: storeURL,
            entryID: entryID,
            revisionID: revisionID,
            createdAt: createdAt,
            rating: rating,
            notes: notes
        )

        let schema = Schema(versionedSchema: ParmaSchemaV3.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: ParmaMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let entries = try context.fetch(FetchDescriptor<ParmaEntry>())
        let venues = try context.fetch(FetchDescriptor<Venue>())

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(venues.count, 1)
        XCTAssertEqual(entries[0].id, entryID)
        XCTAssertEqual(entries[0].venue?.id, entryID)
        XCTAssertEqual(entries[0].venueName, "Migration Hotel")
        XCTAssertEqual(entries[0].latitude, -37.81)
        XCTAssertEqual(entries[0].currentRating, rating)
        XCTAssertEqual(entries[0].notes, notes)
        XCTAssertEqual(entries[0].photoFilename, "migration.jpg")
        XCTAssertEqual(entries[0].createdAt, createdAt)
        XCTAssertEqual(entries[0].revisions.map(\.id), [revisionID])
        XCTAssertNil(venues[0].locality)
        XCTAssertFalse(venues[0].excludedFromRerun)
    }

    func testV2StoreMigratesToV3WithLocalityAndRerunDefaults() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ParmaMasterMigrationV2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "migration-v2.store")
        let entryID = UUID()
        let venueID = UUID()
        let revisionID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let rating = makeRating(parma: 4, chips: 2, salad: 2)
        let notes = AttributedString("V2 migration notes")

        try createV2Store(
            at: storeURL,
            entryID: entryID,
            venueID: venueID,
            revisionID: revisionID,
            createdAt: createdAt,
            rating: rating,
            notes: notes
        )

        let schema = Schema(versionedSchema: ParmaSchemaV3.self)
        let configuration = ModelConfiguration("migration-v2", schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: ParmaMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let entries = try context.fetch(FetchDescriptor<ParmaEntry>())
        let venues = try context.fetch(FetchDescriptor<Venue>())

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(venues.count, 1)
        XCTAssertEqual(entries[0].id, entryID)
        XCTAssertEqual(venues[0].id, venueID)
        XCTAssertEqual(entries[0].venue?.id, venueID)
        XCTAssertEqual(entries[0].venueName, "V2 Hotel")
        XCTAssertEqual(entries[0].latitude, -37.81)
        XCTAssertEqual(entries[0].currentRating, rating)
        XCTAssertEqual(entries[0].notes, notes)
        XCTAssertEqual(entries[0].photoFilename, "v2.jpg")
        XCTAssertEqual(entries[0].createdAt, createdAt)
        XCTAssertEqual(entries[0].revisions.map(\.id), [revisionID])
        XCTAssertNil(venues[0].locality)
        XCTAssertFalse(venues[0].excludedFromRerun)
    }

    func testAppSettingsSnapshotMissingRerunKeysUsesDefaults() throws {
        let json = """
        {
          "hasCompletedOnboarding": true,
          "theme": "Dark",
          "accentHex": "#112233",
          "photoFeatureEnabled": false,
          "locationUseEnabled": true,
          "locationRemindersEnabled": true,
          "automaticBackupsEnabled": true
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(AppSettingsSnapshot.self, from: json)
        XCTAssertTrue(snapshot.hasCompletedOnboarding)
        XCTAssertEqual(snapshot.theme, .dark)
        XCTAssertEqual(snapshot.accentHex, "#112233")
        XCTAssertFalse(snapshot.photoFeatureEnabled)
        XCTAssertTrue(snapshot.locationUseEnabled)
        XCTAssertTrue(snapshot.rerunSuggestionsEnabled)
        XCTAssertEqual(snapshot.rerunStaleMonths, 5)
        XCTAssertEqual(snapshot.rerunHideMonths, 1)
    }

    func testVenueBackupRoundtripPreservesLocalityAndExclusion() throws {
        let venueID = UUID()
        let original = VenueBackup(
            id: venueID,
            mapItemIdentifier: "map-roundtrip",
            venueIdentity: "map:map-roundtrip",
            name: "Roundtrip Hotel",
            formattedAddress: "1 Test Street, Melbourne VIC",
            latitude: -37.81,
            longitude: 144.96,
            locality: "Fitzroy",
            excludedFromRerun: true
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VenueBackup.self, from: encoded)

        XCTAssertEqual(decoded.id, venueID)
        XCTAssertEqual(decoded.locality, "Fitzroy")
        XCTAssertTrue(decoded.excludedFromRerun)
        XCTAssertEqual(decoded.name, "Roundtrip Hotel")
    }

    func testVenueBackupMissingNewKeysDecodesWithDefaults() throws {
        let venueID = UUID()
        let json = """
        {
          "id": "\(venueID.uuidString)",
          "mapItemIdentifier": "map-legacy",
          "venueIdentity": "map:map-legacy",
          "name": "Legacy Hotel",
          "formattedAddress": "1 Test Street, Melbourne VIC",
          "latitude": -37.81,
          "longitude": 144.96
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(VenueBackup.self, from: json)
        XCTAssertEqual(decoded.id, venueID)
        XCTAssertNil(decoded.locality)
        XCTAssertFalse(decoded.excludedFromRerun)
    }

    func testRerunSuggestionRequiresStaleRatingAndRespectsExclusion() {
        let suiteName = "RerunEligibility-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 11))!
        let settingsSuite = "RerunEligibilitySettings-\(UUID().uuidString)"
        let settingsDefaults = UserDefaults(suiteName: settingsSuite)!
        defer { settingsDefaults.removePersistentDomain(forName: settingsSuite) }
        let settings = AppSettings(defaults: settingsDefaults)
        settings.rerunSuggestionsEnabled = true
        settings.rerunStaleMonths = 5
        settings.rerunHideMonths = 1

        let stale = makeEntry(
            name: "Stale Pub",
            rating: makeRating(parma: 4, chips: 2, salad: 2),
            currentRatingDate: calendar.date(byAdding: .month, value: -6, to: now)!
        )
        let fresh = makeEntry(
            name: "Fresh Pub",
            rating: makeRating(parma: 4, chips: 2, salad: 2),
            currentRatingDate: calendar.date(byAdding: .month, value: -1, to: now)!
        )
        let excluded = makeEntry(
            name: "Excluded Pub",
            rating: makeRating(parma: 4, chips: 2, salad: 2),
            currentRatingDate: calendar.date(byAdding: .month, value: -8, to: now)!
        )
        excluded.venue?.excludedFromRerun = true

        let service = RerunSuggestionService(defaults: defaults, calendar: calendar)
        service.update(entries: [stale, fresh, excluded], settings: settings, hasLocationCandidate: false, now: now)

        XCTAssertEqual(service.suggestedEntry?.id, stale.id)
        XCTAssertTrue(service.shouldShowCard)
    }

    func testRerunSuggestionDismissHidesCardForConfiguredMonths() {
        let suiteName = "RerunHide-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 11))!
        let settingsSuite = "RerunHideSettings-\(UUID().uuidString)"
        let settingsDefaults = UserDefaults(suiteName: settingsSuite)!
        defer { settingsDefaults.removePersistentDomain(forName: settingsSuite) }
        let settings = AppSettings(defaults: settingsDefaults)
        settings.rerunHideMonths = 2

        let stale = makeEntry(
            name: "Hide Pub",
            rating: makeRating(parma: 4, chips: 2, salad: 2),
            currentRatingDate: calendar.date(byAdding: .month, value: -6, to: now)!
        )
        let service = RerunSuggestionService(defaults: defaults, calendar: calendar)
        service.update(entries: [stale], settings: settings, hasLocationCandidate: false, now: now)
        XCTAssertTrue(service.shouldShowCard)

        service.dismiss(settings: settings, now: now)
        service.update(entries: [stale], settings: settings, hasLocationCandidate: false, now: now)
        XCTAssertFalse(service.shouldShowCard)

        let stillHidden = calendar.date(byAdding: .month, value: 1, to: now)!
        service.update(entries: [stale], settings: settings, hasLocationCandidate: false, now: stillHidden)
        XCTAssertFalse(service.shouldShowCard)

        let visibleAgain = calendar.date(byAdding: .month, value: 2, to: now)!
        service.update(entries: [stale], settings: settings, hasLocationCandidate: false, now: visibleAgain)
        XCTAssertTrue(service.shouldShowCard)
    }

    func testRerunSuggestionAutoHidesAfterSuggestedEntryIsRelogged() {
        let suiteName = "RerunAutoHide-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 11))!
        let settingsSuite = "RerunAutoHideSettings-\(UUID().uuidString)"
        let settingsDefaults = UserDefaults(suiteName: settingsSuite)!
        defer { settingsDefaults.removePersistentDomain(forName: settingsSuite) }
        let settings = AppSettings(defaults: settingsDefaults)
        settings.rerunHideMonths = 1

        let ratingDate = calendar.date(byAdding: .month, value: -7, to: now)!
        let entry = makeEntry(
            name: "Relog Pub",
            rating: makeRating(parma: 4, chips: 2, salad: 2),
            currentRatingDate: ratingDate
        )
        let service = RerunSuggestionService(defaults: defaults, calendar: calendar)
        service.update(entries: [entry], settings: settings, hasLocationCandidate: false, now: now)
        XCTAssertTrue(service.shouldShowCard)

        entry.currentRatingDate = now
        service.update(entries: [entry], settings: settings, hasLocationCandidate: false, now: now)
        XCTAssertFalse(service.shouldShowCard)
    }

    func testRerunSuggestionYieldsToLocationCandidate() {
        let suiteName = "RerunYield-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 11))!
        let settingsSuite = "RerunYieldSettings-\(UUID().uuidString)"
        let settingsDefaults = UserDefaults(suiteName: settingsSuite)!
        defer { settingsDefaults.removePersistentDomain(forName: settingsSuite) }
        let settings = AppSettings(defaults: settingsDefaults)

        let stale = makeEntry(
            name: "Yield Pub",
            rating: makeRating(parma: 4, chips: 2, salad: 2),
            currentRatingDate: calendar.date(byAdding: .month, value: -6, to: now)!
        )
        let service = RerunSuggestionService(defaults: defaults, calendar: calendar)
        service.update(entries: [stale], settings: settings, hasLocationCandidate: true, now: now)
        XCTAssertNotNil(service.suggestedEntry)
        XCTAssertFalse(service.shouldShowCard)
    }

    func testRerunGapFormattingUsesMonthsAndYears() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 11))!

        XCTAssertEqual(
            RerunSuggestionService.formatGap(
                from: calendar.date(byAdding: .month, value: -5, to: now)!,
                to: now,
                calendar: calendar
            ),
            "5 months"
        )
        XCTAssertEqual(
            RerunSuggestionService.formatGap(
                from: calendar.date(byAdding: .month, value: -1, to: now)!,
                to: now,
                calendar: calendar
            ),
            "1 month"
        )
        XCTAssertEqual(
            RerunSuggestionService.formatGap(
                from: calendar.date(byAdding: .year, value: -1, to: now)!,
                to: now,
                calendar: calendar
            ),
            "1 year"
        )
        XCTAssertEqual(
            RerunSuggestionService.formatGap(
                from: calendar.date(byAdding: .year, value: -2, to: now)!,
                to: now,
                calendar: calendar
            ),
            "2 years"
        )
    }

    func testLegacyBackupUpgradesToSeparatedVenuePayload() throws {
        let entry = makeEntry(name: "Backup Hotel", rating: makeRating(parma: 4, chips: 2, salad: 2))
        let legacy = LegacyBackupPayloadV1(
            schemaVersion: 1,
            exportedAt: .now,
            settings: AppSettingsSnapshot(),
            entries: [LegacyEntryBackupV1(
                id: entry.id,
                venueIdentity: entry.venueIdentity,
                mapItemIdentifier: entry.mapItemIdentifier,
                venueName: entry.venueName,
                formattedAddress: entry.formattedAddress,
                latitude: entry.latitude,
                longitude: entry.longitude,
                createdAt: entry.createdAt,
                currentRatingDate: entry.currentRatingDate,
                lastModifiedAt: entry.lastModifiedAt,
                currentRating: entry.currentRating,
                notesData: entry.notesData,
                photoFilename: "backup.jpg",
                photoData: Data([1, 2, 3]),
                revisions: []
            )]
        )

        let upgraded = legacy.upgraded()
        XCTAssertEqual(upgraded.schemaVersion, 2)
        XCTAssertEqual(upgraded.venues.count, 1)
        XCTAssertEqual(upgraded.entries.first?.venueID, upgraded.venues.first?.id)
        XCTAssertEqual(upgraded.entries.first?.photoData, Data([1, 2, 3]))
    }

    func testCurrentUserProfilePersistsDisplayNameLocally() {
        let suiteName = "CurrentUserProfileTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let profile = CurrentUserProfile(defaults: defaults)
        XCTAssertEqual(profile.displayName, "Hamish")
        profile.displayName = "Test User"
        XCTAssertEqual(CurrentUserProfile(defaults: defaults).displayName, "Test User")
        XCTAssertTrue(HomeGreeting.candidates(at: greetingDate(hour: 9), calendar: greetingCalendar).contains("Welcome back."))
    }

    func testHomeGreetingSessionKeepsOneGreetingForItsLifetime() {
        let session = HomeGreetingSession()
        XCTAssertEqual(session.message, session.message)
    }

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

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Venue.self, ParmaEntry.self, RatingRevision.self, configurations: configuration)
        return ModelContext(container)
    }

    private func createV1Store(
        at url: URL,
        entryID: UUID,
        revisionID: UUID,
        createdAt: Date,
        rating: RatingSnapshot,
        notes: AttributedString
    ) throws {
        let schema = Schema(versionedSchema: ParmaSchemaV1.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let revision = ParmaSchemaV1.RatingRevision(
            id: revisionID,
            timestamp: createdAt,
            ratingData: try JSONEncoder().encode(rating)
        )
        let entry = ParmaSchemaV1.ParmaEntry(
            id: entryID,
            venueIdentity: "map:migration-place",
            mapItemIdentifier: "migration-place",
            venueName: "Migration Hotel",
            formattedAddress: "1 Test Street, Melbourne VIC",
            latitude: -37.81,
            longitude: 144.96,
            createdAt: createdAt,
            currentRatingDate: createdAt.addingTimeInterval(10),
            lastModifiedAt: createdAt.addingTimeInterval(20),
            currentRatingData: try JSONEncoder().encode(rating),
            notesData: try JSONEncoder().encode(notes),
            photoFilename: "migration.jpg",
            revisions: [revision]
        )
        revision.entry = entry
        context.insert(entry)
        try context.save()
    }

    private func createV2Store(
        at url: URL,
        entryID: UUID,
        venueID: UUID,
        revisionID: UUID,
        createdAt: Date,
        rating: RatingSnapshot,
        notes: AttributedString
    ) throws {
        let schema = Schema(versionedSchema: ParmaSchemaV2.self)
        let configuration = ModelConfiguration("migration-v2", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let venue = ParmaSchemaV2.Venue(
            id: venueID,
            mapItemIdentifier: "v2-place",
            venueIdentity: "map:v2-place",
            name: "V2 Hotel",
            formattedAddress: "1 Test Street, Melbourne VIC",
            latitude: -37.81,
            longitude: 144.96
        )
        let revision = ParmaSchemaV2.RatingRevision(
            id: revisionID,
            timestamp: createdAt,
            rating: rating
        )
        let entry = ParmaSchemaV2.ParmaEntry(
            id: entryID,
            venue: venue,
            createdAt: createdAt,
            currentRatingDate: createdAt.addingTimeInterval(10),
            lastModifiedAt: createdAt.addingTimeInterval(20),
            rating: rating,
            notes: notes,
            photoFilename: "v2.jpg",
            revisions: [revision]
        )
        revision.entry = entry
        context.insert(venue)
        context.insert(entry)
        try context.save()
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

    private func makeEntry(
        name: String,
        rating: RatingSnapshot,
        currentRatingDate: Date = .now
    ) -> ParmaEntry {
        let candidate = venue(name: name)
        return ParmaEntry(
            venueIdentity: VenueIdentity.key(for: candidate),
            mapItemIdentifier: candidate.mapItemIdentifier,
            venueName: name,
            formattedAddress: candidate.formattedAddress,
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            currentRatingDate: currentRatingDate,
            rating: rating
        )
    }
}
