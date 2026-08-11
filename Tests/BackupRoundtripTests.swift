import SwiftData
import UIKit
import XCTest
@testable import ParmaMaster

@MainActor
final class BackupRoundtripTests: XCTestCase {
    func testBackupThenRestoreRoundTripsEntriesPhotosAndSettings() async throws {
        let fileManager = FileManager.default
        let photosDirectory = fileManager.temporaryDirectory
            .appending(path: "BackupRoundtripPhotos-\(UUID().uuidString)")
        let backupDirectory = fileManager.temporaryDirectory
            .appending(path: "BackupRoundtripBackups-\(UUID().uuidString)")
        try fileManager.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: photosDirectory)
            try? fileManager.removeItem(at: backupDirectory)
        }

        let backupSuite = "BackupRoundtrip-\(UUID().uuidString)"
        let settingsSuite = "BackupRoundtripSettings-\(UUID().uuidString)"
        let backupDefaults = try XCTUnwrap(UserDefaults(suiteName: backupSuite))
        let settingsDefaults = try XCTUnwrap(UserDefaults(suiteName: settingsSuite))
        defer {
            backupDefaults.removePersistentDomain(forName: backupSuite)
            settingsDefaults.removePersistentDomain(forName: settingsSuite)
        }

        let container = try ModelContainer(
            for: Venue.self, ParmaEntry.self, RatingRevision.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let repository = LocalParmaRepository()
        let photoStore = PhotoStore(directoryURL: photosDirectory)

        let settings = AppSettings(defaults: settingsDefaults)
        settings.theme = .dark
        settings.rerunStaleMonths = 7

        let filename = try photoStore.save(imageData: try XCTUnwrap(makeTestImageData()))
        let candidate = VenueCandidate(
            mapItemIdentifier: "map-roundtrip-hotel",
            name: "Roundtrip Hotel",
            formattedAddress: "1 Test Street, Melbourne VIC",
            latitude: -37.81,
            longitude: 144.96
        )
        try repository.create(
            venue: candidate,
            rating: makeRating(parma: 4, chips: 2, salad: 2),
            notes: AttributedString("Roundtrip note"),
            photoFilename: filename,
            in: context
        )

        let backupService = BackupService(defaults: backupDefaults)
        backupService.configure(context: context, settings: settings, photoStore: photoStore)
        try backupService.chooseBackupDirectory(backupDirectory)
        try await backupService.backupNow()

        let backupURL = backupDirectory.appending(path: BackupTuning.backupFilename)
        XCTAssertTrue(fileManager.fileExists(atPath: backupURL.path))
        XCTAssertNotNil(backupService.lastSuccessfulBackup)

        try repository.reset(photoStore: photoStore, in: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ParmaEntry>()).isEmpty)

        // Diverge the settings so the restore visibly reapplies the snapshot.
        settings.theme = .light
        settings.rerunStaleMonths = 5

        try await backupService.restore(from: backupURL)

        let restoredEntries = try context.fetch(FetchDescriptor<ParmaEntry>())
        XCTAssertEqual(restoredEntries.count, 1)
        let restored = try XCTUnwrap(restoredEntries.first)
        XCTAssertEqual(restored.venueName, "Roundtrip Hotel")
        XCTAssertEqual(restored.currentRating.total, 8)
        XCTAssertEqual(restored.searchableNotes, "Roundtrip note")
        XCTAssertEqual(restored.photoFilename, filename)
        XCTAssertNotNil(photoStore.data(for: filename))
        XCTAssertEqual(settings.theme, .dark)
        XCTAssertEqual(settings.rerunStaleMonths, 7)
    }

    func testRestoreRejectsACorruptBackupFile() async throws {
        let fileManager = FileManager.default
        let photosDirectory = fileManager.temporaryDirectory
            .appending(path: "BackupCorruptPhotos-\(UUID().uuidString)")
        let workingDirectory = fileManager.temporaryDirectory
            .appending(path: "BackupCorrupt-\(UUID().uuidString)")
        try fileManager.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: photosDirectory)
            try? fileManager.removeItem(at: workingDirectory)
        }

        let backupSuite = "BackupCorrupt-\(UUID().uuidString)"
        let settingsSuite = "BackupCorruptSettings-\(UUID().uuidString)"
        let backupDefaults = try XCTUnwrap(UserDefaults(suiteName: backupSuite))
        let settingsDefaults = try XCTUnwrap(UserDefaults(suiteName: settingsSuite))
        defer {
            backupDefaults.removePersistentDomain(forName: backupSuite)
            settingsDefaults.removePersistentDomain(forName: settingsSuite)
        }

        let container = try ModelContainer(
            for: Venue.self, ParmaEntry.self, RatingRevision.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let photoStore = PhotoStore(directoryURL: photosDirectory)
        let settings = AppSettings(defaults: settingsDefaults)

        let corruptURL = workingDirectory.appending(path: "Corrupt.parmabackup")
        try Data("not json".utf8).write(to: corruptURL)

        let backupService = BackupService(defaults: backupDefaults)
        backupService.configure(context: context, settings: settings, photoStore: photoStore)

        do {
            try await backupService.restore(from: corruptURL)
            XCTFail("Restoring a corrupt backup file should throw")
        } catch {
            // Expected: the corrupt payload must be rejected.
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<ParmaEntry>()).isEmpty)
    }

    private func makeTestImageData() -> Data? {
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData()
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
