import CoreLocation
import Foundation
import MapKit
import Network
import SwiftData

/// Resolves and persists a venue's MapKit area name (`Venue.locality`) via reverse geocoding.
@MainActor
enum AreaResolutionService {
    /// Max venues to reverse-geocode per backfill pass (app launch).
    private static let backfillBatchLimit = 8
    /// Brief pause between geocode requests to avoid hammering MapKit.
    private static let backfillSpacingNanoseconds: UInt64 = 250_000_000

    /// Best-effort fire-and-forget resolve after create/update. Does not block the caller.
    static func scheduleResolveIfNeeded(_ venue: Venue?, in context: ModelContext) {
        guard let venue else { return }
        Task { await resolveIfNeeded(venue, in: context) }
    }

    /// Resolves locality for a single venue when missing. Failures leave `locality` nil.
    static func resolveIfNeeded(_ venue: Venue, in context: ModelContext) async {
        guard let name = await resolvedAreaName(for: venue) else { return }
        guard needsResolution(venue) else { return }
        venue.locality = name
        try? context.save()
    }

    /// Backfill for venues with missing locality. Skips when offline; throttled batch.
    /// Resolved names are applied and saved once at the end so observers (e.g. the Home
    /// areas count) see a single update rather than the count visibly ticking up.
    static func backfillMissingLocalities(in context: ModelContext) async {
        guard await isNetworkSatisfied() else { return }

        let venues: [Venue]
        do {
            venues = try context.fetch(FetchDescriptor<Venue>())
        } catch {
            return
        }

        let pending = venues
            .filter { needsResolution($0) && hasValidCoordinate($0) }
            .prefix(backfillBatchLimit)
        guard !pending.isEmpty else { return }

        var resolved: [(Venue, String)] = []
        for venue in pending {
            if let name = await resolvedAreaName(for: venue) {
                resolved.append((venue, name))
            }
            try? await Task.sleep(nanoseconds: backfillSpacingNanoseconds)
        }

        guard !resolved.isEmpty else { return }
        for (venue, name) in resolved where needsResolution(venue) {
            venue.locality = name
        }
        try? context.save()
    }

    // MARK: - Internals

    private static func needsResolution(_ venue: Venue) -> Bool {
        guard let locality = venue.locality?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return true
        }
        return locality.isEmpty
    }

    private static func hasValidCoordinate(_ venue: Venue) -> Bool {
        let coordinate = CLLocationCoordinate2D(latitude: venue.latitude, longitude: venue.longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return false }
        return !(venue.latitude == 0 && venue.longitude == 0)
    }

    /// Reverse geocodes and returns the preferred area name without mutating the venue.
    private static func resolvedAreaName(for venue: Venue) async -> String? {
        guard needsResolution(venue), hasValidCoordinate(venue) else { return nil }
        do {
            return try await reverseGeocodeAreaName(
                latitude: venue.latitude,
                longitude: venue.longitude
            )
        } catch {
            // Best-effort: leave locality nil for a later backfill.
            return nil
        }
    }

    private static func reverseGeocodeAreaName(latitude: Double, longitude: Double) async throws -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        let mapItems = try await request.mapItems
        guard let mapItem = mapItems.first else { return nil }
        return preferredAreaName(from: mapItem)
    }

    /// `addressRepresentations.cityName` is MapKit's iOS 26 locality (suburb/town) source.
    /// Venues that resolve without a city name stay unresolved for a later backfill pass.
    private static func preferredAreaName(from mapItem: MKMapItem) -> String? {
        cleaned(mapItem.addressRepresentations?.cityName)
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func isNetworkSatisfied() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "ParmaMaster.AreaResolution.Path")
            let state = OnceResume()
            monitor.pathUpdateHandler = { path in
                state.resume {
                    monitor.cancel()
                    continuation.resume(returning: path.status == .satisfied)
                }
            }
            monitor.start(queue: queue)
        }
    }
}

/// Ensures a continuation resumes only once from `NWPathMonitor` callbacks.
private final class OnceResume: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func resume(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        body()
    }
}
