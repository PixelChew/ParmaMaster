import CoreLocation
import Foundation
import MapKit

struct InsightsEntryRecord: Sendable, Identifiable, Hashable {
    let id: UUID
    let venueID: UUID
    let venueName: String
    let locality: String?
    let latitude: Double
    let longitude: Double
    let createdAt: Date
    let currentRatingDate: Date
    let lastModifiedAt: Date
    let rating: RatingSnapshot
    let revisionCount: Int
    let photoFilename: String?
}

struct VenuePin: Identifiable, Sendable, Equatable {
    let id: UUID
    let entryID: UUID
    let title: String
    let latitude: Double
    let longitude: Double
    let scoreText: String
    let accessibilityText: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ParmaInsights: Sendable {
    let entries: [InsightsEntryRecord]
    let averageNormalisedScore: Decimal?
    let highestNormalisedScore: Decimal?
    let lowestNormalisedScore: Decimal?
    let highestEntries: [InsightsEntryRecord]
    let lowestEntries: [InsightsEntryRecord]
    let perfectEntries: [InsightsEntryRecord]
    let ratingsSubmitted: Int
    let parmasLoggedThisYear: Int
    let areasVisited: Int
    let mostRecentlyLogged: InsightsEntryRecord?
    let componentAverages: [RatingCategory: Decimal]

    var parmasLogged: Int { entries.count }
}

struct InsightsSnapshot: Sendable {
    let cacheKey: InsightsCacheKey
    let insights: ParmaInsights
    let pins: [VenuePin]
    let mapCacheSignature: Int
    let areas: [AreaSummary]
}

struct InsightsCacheKey: Equatable, Sendable {
    let entryCount: Int
    let maxLastModified: Date?
    let contentSignature: Int
}

enum ParmaInsightsCalculator {
    static func calculate(
        _ entries: [InsightsEntryRecord],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> ParmaInsights {
        let validEntries = entries.filter { $0.rating.hasValidScores }
        let scores = validEntries.map { $0.rating.normalisedScore }
        let average = scores.isEmpty ? nil : scores.reduce(0, +) / Decimal(scores.count)
        let highest = scores.max()
        let lowest = scores.min()
        let highestEntries = highest.map { score in validEntries.filter { $0.rating.normalisedScore == score } } ?? []
        let lowestEntries = lowest.map { score in validEntries.filter { $0.rating.normalisedScore == score } } ?? []
        let componentPairs: [(RatingCategory, Decimal)] = RatingCategory.allCases.compactMap { category in
            let values = validEntries.compactMap { record -> Decimal? in
                guard let component = record.rating.components.first(where: { $0.category == category }),
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
            entries.compactMap { record -> String? in
                guard let locality = AreaNameResolver.cleaned(record.locality) else { return nil }
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
            perfectEntries: validEntries.filter { $0.rating.total == $0.rating.maximum },
            ratingsSubmitted: entries.count + entries.reduce(0) { $0 + $1.revisionCount },
            parmasLoggedThisYear: entries.filter { calendar.isDate($0.createdAt, equalTo: now, toGranularity: .year) }.count,
            areasVisited: uniqueLocalities.count,
            mostRecentlyLogged: entries.max { $0.createdAt < $1.createdAt },
            componentAverages: componentAverages
        )
    }

    static func venuePins(from records: [InsightsEntryRecord]) -> [VenuePin] {
        var seenVenueIDs = Set<UUID>()
        var pins: [VenuePin] = []
        for record in records {
            let coordinate = CLLocationCoordinate2D(latitude: record.latitude, longitude: record.longitude)
            guard CLLocationCoordinate2DIsValid(coordinate),
                  !(record.latitude == 0 && record.longitude == 0) else { continue }
            guard seenVenueIDs.insert(record.venueID).inserted else { continue }
            let equivalent = record.rating.normalisedScore.tenPointEquivalent
            pins.append(
                VenuePin(
                    id: record.venueID,
                    entryID: record.id,
                    title: record.venueName,
                    latitude: record.latitude,
                    longitude: record.longitude,
                    scoreText: equivalent.rounded(scale: 1).displayString,
                    accessibilityText: "\(record.venueName), \(equivalent.insightScoreString) equivalent"
                )
            )
        }
        return pins
    }

    static func mapRegion(for pins: [VenuePin]) -> MKCoordinateRegion {
        let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        let fallback = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9631),
            span: defaultSpan
        )
        guard let first = pins.first else { return fallback }
        if pins.count == 1 {
            return MKCoordinateRegion(center: first.coordinate, span: defaultSpan)
        }

        let latitudes = pins.map(\.latitude)
        let longitudes = pins.map(\.longitude)
        let minLat = latitudes.min()!
        let maxLat = latitudes.max()!
        let minLon = longitudes.min()!
        let maxLon = longitudes.max()!
        let fittedLat = max((maxLat - minLat) * 1.35, 0.02)
        let fittedLon = max((maxLon - minLon) * 1.35, 0.02)
        let maxSpan = InsightsTuning.maxCardSpan
        if fittedLat <= maxSpan, fittedLon <= maxSpan {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                span: MKCoordinateSpan(latitudeDelta: fittedLat, longitudeDelta: fittedLon)
            )
        }

        // A midpoint between distant cities can be hundreds of kilometres from
        // every venue. Keep the capped card useful by anchoring it on the first
        // (most-recent, in the store fetch) pin instead.
        return MKCoordinateRegion(
            center: first.coordinate,
            span: MKCoordinateSpan(latitudeDelta: maxSpan, longitudeDelta: maxSpan)
        )
    }

    static func cacheKey(for records: [InsightsEntryRecord]) -> InsightsCacheKey {
        var hasher = Hasher()
        for record in records.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(record.id)
            hasher.combine(record.venueID)
            hasher.combine(record.venueName)
            hasher.combine(record.locality)
            hasher.combine(record.latitude)
            hasher.combine(record.longitude)
            hasher.combine(record.createdAt)
            hasher.combine(record.currentRatingDate)
            hasher.combine(record.lastModifiedAt)
            hasher.combine(record.rating)
            hasher.combine(record.revisionCount)
            hasher.combine(record.photoFilename)
        }
        return InsightsCacheKey(
            entryCount: records.count,
            maxLastModified: records.map(\.lastModifiedAt).max(),
            contentSignature: hasher.finalize()
        )
    }

    static func mapCacheSignature(for pins: [VenuePin]) -> Int {
        var hasher = Hasher()
        for pin in pins {
            hasher.combine(pin.id)
            hasher.combine(pin.entryID)
            hasher.combine(pin.title)
            hasher.combine(pin.latitude)
            hasher.combine(pin.longitude)
            hasher.combine(pin.scoreText)
        }
        return hasher.finalize()
    }

    static func records(from entries: [ParmaEntry]) -> [InsightsEntryRecord] {
        entries.map { entry in
            InsightsEntryRecord(
                id: entry.id,
                venueID: entry.venue?.id ?? entry.id,
                venueName: entry.venueName,
                locality: entry.venue?.locality,
                latitude: entry.latitude,
                longitude: entry.longitude,
                createdAt: entry.createdAt,
                currentRatingDate: entry.currentRatingDate,
                lastModifiedAt: entry.lastModifiedAt,
                rating: entry.currentRating,
                revisionCount: entry.revisions.count,
                photoFilename: entry.photoFilename
            )
        }
    }
}

extension Decimal {
    var tenPointEquivalent: Decimal { self * 10 }

    var insightScoreString: String {
        let rounded = rounded(scale: 2)
        return "\(rounded.displayString)/10"
    }
}
