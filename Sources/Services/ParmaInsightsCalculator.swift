import Foundation

struct ParmaInsights {
    let entries: [ParmaEntry]
    let averageNormalisedScore: Decimal?
    let highestNormalisedScore: Decimal?
    let lowestNormalisedScore: Decimal?
    let highestEntries: [ParmaEntry]
    let lowestEntries: [ParmaEntry]
    let perfectEntries: [ParmaEntry]
    let mostRevisitedEntries: [ParmaEntry]
    let ratingsSubmitted: Int
    let parmasLoggedThisYear: Int
    let areasVisited: Int
    let mostRecentlyLogged: ParmaEntry?
    let componentAverages: [RatingCategory: Decimal]

    var parmasLogged: Int { entries.count }
}

enum ParmaInsightsCalculator {
    static func calculate(
        _ entries: [ParmaEntry],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> ParmaInsights {
        // `currentRating` JSON-decodes on every access, so decode each entry's
        // rating exactly once here — repeated access was expensive enough to
        // hang the main thread on Insights' first render.
        let rated = entries.map { (entry: $0, rating: $0.currentRating) }
        let validEntries = rated.filter { $0.rating.hasValidScores }
        let scores = validEntries.map { $0.rating.normalisedScore }
        let average = scores.isEmpty ? nil : scores.reduce(0, +) / Decimal(scores.count)
        let highest = scores.max()
        let lowest = scores.min()
        let highestEntries = highest.map { score in validEntries.filter { $0.rating.normalisedScore == score }.map(\.entry) } ?? []
        let lowestEntries = lowest.map { score in validEntries.filter { $0.rating.normalisedScore == score }.map(\.entry) } ?? []
        let highestRevisionCount = entries.map { $0.revisions.count }.max() ?? 0
        let componentPairs: [(RatingCategory, Decimal)] = RatingCategory.allCases.compactMap { category in
            let values = validEntries.compactMap { pair -> Decimal? in
                guard let component = pair.rating.components.first(where: { $0.category == category }),
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
        let uniqueLocalities = Set(
            entries.compactMap { entry -> String? in
                guard let locality = AreaNameResolver.cleaned(entry.venue?.locality) else { return nil }
                return AreaNameResolver.normalisedKey(locality)
            }
        )

        return ParmaInsights(
            entries: entries,
            averageNormalisedScore: average,
            highestNormalisedScore: highest,
            lowestNormalisedScore: lowest,
            highestEntries: highestEntries,
            lowestEntries: lowestEntries,
            perfectEntries: validEntries.filter { $0.rating.total == $0.rating.maximum }.map(\.entry),
            mostRevisitedEntries: highestRevisionCount > 0 ? entries.filter { $0.revisions.count == highestRevisionCount } : [],
            ratingsSubmitted: entries.count + entries.reduce(0) { $0 + $1.revisions.count },
            parmasLoggedThisYear: entries.filter { calendar.isDate($0.createdAt, equalTo: now, toGranularity: .year) }.count,
            areasVisited: uniqueLocalities.count,
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
