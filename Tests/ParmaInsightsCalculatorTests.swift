import XCTest
@testable import ParmaMaster

@MainActor
final class ParmaInsightsCalculatorTests: XCTestCase {
    func testAverageUsesNormalisedScoresAcrossDifferentScales() {
        let insights = ParmaInsightsCalculator.calculate([
            entry("Eight", score: 8, maximum: 10),
            entry("Twelve", score: 12, maximum: 15)
        ])

        XCTAssertEqual(insights.averageNormalisedScore, Decimal(string: "0.8"))
        XCTAssertEqual(insights.averageNormalisedScore?.tenPointEquivalent, 8)
    }

    func testExtremesPreserveTiesAndPerfectScoresUseActualMaximum() {
        let perfectTen = entry("Ten", score: 10, maximum: 10)
        let perfectFifteen = entry("Fifteen", score: 15, maximum: 15)
        let almost = entry("Almost", score: 9.5, maximum: 10)
        let low = entry("Low", score: 6, maximum: 10)
        let insights = ParmaInsightsCalculator.calculate([perfectTen, perfectFifteen, almost, low])

        XCTAssertEqual(Set(insights.highestEntries.map(\.id)), Set([perfectTen.id, perfectFifteen.id]))
        XCTAssertEqual(insights.lowestEntries.map(\.id), [low.id])
        XCTAssertEqual(Set(insights.perfectEntries.map(\.id)), Set([perfectTen.id, perfectFifteen.id]))
    }

    func testHistoryAndComponentAveragesUseCorrectDatasets() {
        let revisited = entry("Revisited", score: 8, maximum: 10, chips: 2, chipsMaximum: 4, revisions: 2)
        let other = entry("Other", score: 6, maximum: 10, chips: nil, chipsMaximum: 4)
        let insights = ParmaInsightsCalculator.calculate([revisited, other])

        XCTAssertEqual(insights.parmasLogged, 2)
        XCTAssertEqual(insights.ratingsSubmitted, 4)
        XCTAssertEqual(insights.mostRevisitedEntries.map(\.id), [revisited.id])
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
        let fitzroyA = entry("Fitzroy A", score: 8, maximum: 10, locality: "Fitzroy")
        let fitzroyB = entry("Fitzroy B", score: 7, maximum: 10, locality: "fitzroy")
        let brunswick = entry("Brunswick", score: 6, maximum: 10, locality: "Brunswick")
        let unresolved = entry("Unresolved", score: 5, maximum: 10, locality: nil)
        let blank = entry("Blank", score: 4, maximum: 10, locality: "   ")
        let insights = ParmaInsightsCalculator.calculate([fitzroyA, fitzroyB, brunswick, unresolved, blank])

        XCTAssertEqual(insights.areasVisited, 2)
        XCTAssertEqual(insights.parmasLogged, 5)
    }

    private func entry(
        _ name: String,
        score: Decimal,
        maximum: Decimal,
        chips: Decimal? = nil,
        chipsMaximum: Decimal = 1,
        revisions: Int = 0,
        locality: String? = nil
    ) -> ParmaEntry {
        let parmaMaximum = maximum - (chips == nil ? 0 : chipsMaximum)
        let rating = RatingSnapshot(
            components: [
                ComponentRatingSnapshot(category: .parma, isEnabled: true, displayMode: .numeric, maximum: parmaMaximum, score: score - (chips ?? 0)),
                ComponentRatingSnapshot(category: .chips, isEnabled: chips != nil, displayMode: .numeric, maximum: chipsMaximum, score: chips),
                ComponentRatingSnapshot(category: .salad, isEnabled: false, displayMode: .numeric, maximum: 1, score: nil)
            ],
            overallDisplayMode: .numeric
        )
        let item = ParmaEntry(venueIdentity: "map:\(name)", mapItemIdentifier: nil, venueName: name, formattedAddress: "Test address", latitude: -37.8, longitude: 144.9, rating: rating)
        item.venue?.locality = locality
        item.revisions = (0..<revisions).map { _ in RatingRevision(timestamp: .now, rating: rating, entry: item) }
        return item
    }
}
