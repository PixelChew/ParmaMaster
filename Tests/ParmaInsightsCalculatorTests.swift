import XCTest
@testable import ParmaMaster

final class ParmaInsightsCalculatorTests: XCTestCase {
    func testAverageUsesNormalisedScoresAcrossDifferentScales() {
        let insights = ParmaInsightsCalculator.calculate([
            record("Eight", score: 8, maximum: 10),
            record("Twelve", score: 12, maximum: 15)
        ])

        XCTAssertEqual(insights.averageNormalisedScore, Decimal(string: "0.8"))
        XCTAssertEqual(insights.averageNormalisedScore?.tenPointEquivalent, 8)
    }

    func testExtremesPreserveTiesAndPerfectScoresUseActualMaximum() {
        let perfectTen = record("Ten", score: 10, maximum: 10)
        let perfectFifteen = record("Fifteen", score: 15, maximum: 15)
        let almost = record("Almost", score: 9.5, maximum: 10)
        let low = record("Low", score: 6, maximum: 10)
        let insights = ParmaInsightsCalculator.calculate([perfectTen, perfectFifteen, almost, low])

        XCTAssertEqual(Set(insights.highestEntries.map(\.id)), Set([perfectTen.id, perfectFifteen.id]))
        XCTAssertEqual(insights.lowestEntries.map(\.id), [low.id])
        XCTAssertEqual(Set(insights.perfectEntries.map(\.id)), Set([perfectTen.id, perfectFifteen.id]))
    }

    func testHistoryAndComponentAveragesUseCorrectDatasets() {
        let revisited = record("Revisited", score: 8, maximum: 10, chips: 2, chipsMaximum: 4, revisions: 2)
        let other = record("Other", score: 6, maximum: 10, chips: nil, chipsMaximum: 4)
        let insights = ParmaInsightsCalculator.calculate([revisited, other])

        XCTAssertEqual(insights.parmasLogged, 2)
        XCTAssertEqual(insights.ratingsSubmitted, 4)
        XCTAssertEqual(insights.componentAverages[.parma], Decimal(string: "0.8"))
        XCTAssertEqual(insights.componentAverages[.chips], Decimal(string: "0.5"))
    }

    func testEmptyInsightsHasNoDerivedScores() {
        let insights = ParmaInsightsCalculator.calculate([])
        XCTAssertEqual(insights.parmasLogged, 0)
        XCTAssertNil(insights.averageNormalisedScore)
        XCTAssertTrue(insights.highestEntries.isEmpty)
        XCTAssertTrue(insights.perfectEntries.isEmpty)
        XCTAssertEqual(insights.ratingsSubmitted, 0)
        XCTAssertEqual(insights.areasVisited, 0)
    }

    func testAreasVisitedDedupesLocalitiesAndIgnoresUnresolved() {
        let fitzroyA = record("Fitzroy A", score: 8, maximum: 10, locality: "Fitzroy")
        let fitzroyB = record("Fitzroy B", score: 7, maximum: 10, locality: "fitzroy")
        let brunswick = record("Brunswick", score: 6, maximum: 10, locality: "Brunswick")
        let unresolved = record("Unresolved", score: 5, maximum: 10, locality: nil)
        let blank = record("Blank", score: 4, maximum: 10, locality: "   ")
        let insights = ParmaInsightsCalculator.calculate([fitzroyA, fitzroyB, brunswick, unresolved, blank])

        XCTAssertEqual(insights.areasVisited, 2)
        XCTAssertEqual(insights.parmasLogged, 5)
    }

    func testSnapshotGenerationUsesValueTypesWithoutLiveModels() {
        let records = [
            record("Alpha", score: 8, maximum: 10, locality: "Fitzroy", latitude: -37.8, longitude: 144.9),
            record("Beta", score: 6, maximum: 10, locality: "Fitzroy", latitude: -37.81, longitude: 144.91)
        ]
        let insights = ParmaInsightsCalculator.calculate(records)
        let pins = ParmaInsightsCalculator.venuePins(from: records)
        let areas = AreaAggregator.areas(from: records)
        let key = ParmaInsightsCalculator.cacheKey(for: records)

        XCTAssertEqual(insights.parmasLogged, 2)
        XCTAssertEqual(pins.count, 2)
        XCTAssertEqual(areas.count, 1)
        XCTAssertEqual(key.entryCount, 2)
        XCTAssertNotNil(key.maxLastModified)
    }

    func testVenuePinsDedupesByVenueAndSkipsInvalidCoordinates() {
        let venueID = UUID()
        let first = record("First", score: 8, maximum: 10, latitude: -37.8, longitude: 144.9, venueID: venueID)
        let duplicateVenue = record("Second visit", score: 9, maximum: 10, latitude: -37.81, longitude: 144.91, venueID: venueID)
        let invalid = record("Nowhere", score: 5, maximum: 10, latitude: 0, longitude: 0)

        let pins = ParmaInsightsCalculator.venuePins(from: [first, duplicateVenue, invalid])
        XCTAssertEqual(pins.map(\.entryID), [first.id])
        XCTAssertEqual(pins.first?.id, venueID)
    }

    func testMapRegionFitsNearbyPinsWithoutUsingTheCap() {
        let pins = ParmaInsightsCalculator.venuePins(from: [
            record("A", score: 8, maximum: 10, latitude: -37.80, longitude: 144.97),
            record("B", score: 7, maximum: 10, latitude: -37.81, longitude: 144.98)
        ])
        let region = ParmaInsightsCalculator.mapRegion(for: pins)
        XCTAssertLessThan(region.span.latitudeDelta, InsightsTuning.maxCardSpan)
        XCTAssertLessThan(region.span.longitudeDelta, InsightsTuning.maxCardSpan)
    }

    func testMapRegionCapsSpanWhenPinsAreFarApart() {
        let pins = ParmaInsightsCalculator.venuePins(from: [
            record("Melbourne", score: 8, maximum: 10, latitude: -37.8136, longitude: 144.9631),
            record("Sydney", score: 7, maximum: 10, latitude: -33.8688, longitude: 151.2093)
        ])
        let region = ParmaInsightsCalculator.mapRegion(for: pins)
        XCTAssertEqual(region.span.latitudeDelta, InsightsTuning.maxCardSpan)
        XCTAssertEqual(region.span.longitudeDelta, InsightsTuning.maxCardSpan)
        XCTAssertEqual(region.center.latitude, pins[0].latitude, accuracy: 0.000_001)
        XCTAssertEqual(region.center.longitude, pins[0].longitude, accuracy: 0.000_001)
    }

    func testCacheKeyChangesWhenLocalityChangesWithoutTimestampChange() {
        let id = UUID()
        let venueID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let unresolved = record(
            "Same venue",
            score: 8,
            maximum: 10,
            locality: nil,
            venueID: venueID,
            id: id,
            timestamp: timestamp
        )
        let resolved = record(
            "Same venue",
            score: 8,
            maximum: 10,
            locality: "Fitzroy",
            venueID: venueID,
            id: id,
            timestamp: timestamp
        )

        XCTAssertNotEqual(
            ParmaInsightsCalculator.cacheKey(for: [unresolved]),
            ParmaInsightsCalculator.cacheKey(for: [resolved])
        )
    }

    private func record(
        _ name: String,
        score: Decimal,
        maximum: Decimal,
        chips: Decimal? = nil,
        chipsMaximum: Decimal = 1,
        revisions: Int = 0,
        locality: String? = nil,
        latitude: Double = -37.8,
        longitude: Double = 144.9,
        venueID: UUID? = nil,
        id: UUID = UUID(),
        timestamp: Date = .now
    ) -> InsightsEntryRecord {
        let parmaMaximum = maximum - (chips == nil ? 0 : chipsMaximum)
        let rating = RatingSnapshot(
            components: [
                ComponentRatingSnapshot(category: .parma, isEnabled: true, displayMode: .numeric, maximum: parmaMaximum, score: score - (chips ?? 0)),
                ComponentRatingSnapshot(category: .chips, isEnabled: chips != nil, displayMode: .numeric, maximum: chipsMaximum, score: chips),
                ComponentRatingSnapshot(category: .salad, isEnabled: false, displayMode: .numeric, maximum: 1, score: nil)
            ],
            overallDisplayMode: .numeric
        )
        return InsightsEntryRecord(
            id: id,
            venueID: venueID ?? UUID(),
            venueName: name,
            locality: locality,
            latitude: latitude,
            longitude: longitude,
            createdAt: timestamp,
            currentRatingDate: timestamp,
            lastModifiedAt: timestamp,
            rating: rating,
            revisionCount: revisions,
            photoFilename: nil
        )
    }
}
