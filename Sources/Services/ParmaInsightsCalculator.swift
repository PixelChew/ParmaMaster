import Foundation

struct ParmaInsights {
    let entries: [ParmaEntry]
    let averageNormalisedScore: Decimal?
    let highestEntries: [ParmaEntry]
    let lowestEntries: [ParmaEntry]
    let perfectEntries: [ParmaEntry]
    let mostRevisitedEntries: [ParmaEntry]
    let ratingsSubmitted: Int
    let parmasLoggedThisYear: Int
    let mostRecentlyLogged: ParmaEntry?
    let componentAverages: [RatingCategory: Decimal]

    var parmasLogged: Int { entries.count }
    var highestNormalisedScore: Decimal? { highestEntries.first?.currentRating.normalisedScore }
    var lowestNormalisedScore: Decimal? { lowestEntries.first?.currentRating.normalisedScore }
}

enum ParmaInsightsCalculator {
    static func calculate(
        _ entries: [ParmaEntry],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> ParmaInsights {
        let validEntries = entries.filter { $0.currentRating.hasValidScores }
        let scores = validEntries.map { $0.currentRating.normalisedScore }
        let average = scores.isEmpty ? nil : scores.reduce(0, +) / Decimal(scores.count)
        let highest = scores.max()
        let lowest = scores.min()
        let highestEntries = highest.map { score in validEntries.filter { $0.currentRating.normalisedScore == score } } ?? []
        let lowestEntries = lowest.map { score in validEntries.filter { $0.currentRating.normalisedScore == score } } ?? []
        let highestRevisionCount = entries.map { $0.revisions.count }.max() ?? 0
        let componentPairs: [(RatingCategory, Decimal)] = RatingCategory.allCases.compactMap { category in
            let values = validEntries.compactMap { entry -> Decimal? in
                guard let component = entry.currentRating.components.first(where: { $0.category == category }),
                      component.isEnabled,
                      let score = component.score,
                      component.maximum > 0,
                      score >= 0,
                      score <= component.maximum else { return nil }
                return score / component.maximum
            }
            guard !values.isEmpty else { return nil }
            return (category, values.reduce(0, +) / Decimal(values.count))
        }
        let componentAverages = Dictionary(uniqueKeysWithValues: componentPairs)

        return ParmaInsights(
            entries: entries,
            averageNormalisedScore: average,
            highestEntries: highestEntries,
            lowestEntries: lowestEntries,
            perfectEntries: validEntries.filter { $0.currentRating.total == $0.currentRating.maximum },
            mostRevisitedEntries: highestRevisionCount > 0 ? entries.filter { $0.revisions.count == highestRevisionCount } : [],
            ratingsSubmitted: entries.count + entries.reduce(0) { $0 + $1.revisions.count },
            parmasLoggedThisYear: entries.filter { calendar.isDate($0.createdAt, equalTo: now, toGranularity: .year) }.count,
            mostRecentlyLogged: entries.max { $0.createdAt < $1.createdAt },
            componentAverages: componentAverages
        )
    }
}

extension Decimal {
    var tenPointEquivalent: Decimal { self * 10 }

    var insightScoreString: String {
        let rounded = rounded(scale: 2)
        return "\(rounded.displayString)/10"
    }
}
