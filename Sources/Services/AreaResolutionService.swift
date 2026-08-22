import CoreLocation
import Foundation
import MapKit
import Network
import os
import SwiftData

/// Resolves and persists a venue's area name (`Venue.locality`) for the
/// Areas visited tally. Prefers MapKit city names, falls back to parsing the
/// stored address (works offline), and reverse-geocodes only when needed.
@MainActor
enum AreaResolutionService {
    /// Venue IDs that failed network resolution this process — skipped so a
    /// stubborn failure cannot permanently block the backfill queue.
    private static var skippedNetworkIDs = Set<UUID>()

    /// Best-effort fire-and-forget resolve after create/update. Does not block the caller.
    static func scheduleResolveIfNeeded(
        _ venue: Venue?,
        in context: ModelContext,
        onChange: (() -> Void)? = nil
    ) {
        guard let venue else { return }
        Task {
            if await resolveIfNeeded(venue, in: context) {
                onChange?()
            }
        }
    }

    /// Resolves locality for a single venue when missing. Failures leave `locality` nil.
    @discardableResult
    static func resolveIfNeeded(_ venue: Venue, in context: ModelContext) async -> Bool {
        guard let name = await resolvedAreaName(for: venue) else { return false }
        guard needsResolution(venue) else { return false }
        venue.locality = name
        do {
            try context.save()
            return true
        } catch {
            AppLog.data.error("Locality save failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Immediate offline fill from a candidate/address, then optional network resolve.
    static func applyImmediateLocality(to venue: Venue, candidateLocality: String?, formattedAddress: String) {
        guard needsResolution(venue) else { return }
        if let name = AreaNameResolver.cleaned(candidateLocality)
            ?? AreaNameResolver.fromFormattedAddress(formattedAddress) {
            venue.locality = name
        }
    }

    /// Backfill for venues with missing locality.
    ///
    /// 1. Offline pass: parse every stored address and save once (no count flicker).
    /// 2. Online pass: reverse-geocode a bounded batch of remaining venues,
    ///    skipping IDs that already failed this launch so the queue advances.
    @discardableResult
    static func backfillMissingLocalities(in context: ModelContext) async -> Bool {
        let venues: [Venue]
        do {
            venues = try context.fetch(FetchDescriptor<Venue>())
        } catch {
            AppLog.data.error("Locality backfill fetch failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        var changed = false

        // 1. Offline address parse — unbounded, no network, single save.
        var parsed: [(Venue, String)] = []
        for venue in venues where needsResolution(venue) {
            if let name = AreaNameResolver.fromFormattedAddress(venue.formattedAddress) {
                parsed.append((venue, name))
            }
        }
        if !parsed.isEmpty {
            for (venue, name) in parsed where needsResolution(venue) {
                venue.locality = name
            }
            do {
                try context.save()
                changed = true
            } catch {
                AppLog.data.error("Locality offline backfill save failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Cheap probe so the steady state skips the network path (audit B-07).
        var probe = FetchDescriptor<Venue>(
            predicate: #Predicate<Venue> { venue in
                venue.locality == nil || venue.locality == ""
            }
        )
        probe.fetchLimit = 1
        do {
            if try context.fetch(probe).isEmpty { return changed }
        } catch {
            AppLog.data.error("Locality backfill probe failed: \(error.localizedDescription, privacy: .public)")
            return changed
        }

        guard await isNetworkSatisfied() else { return changed }

        let remaining: [Venue]
        do {
            remaining = try context.fetch(FetchDescriptor<Venue>())
        } catch {
            AppLog.data.error("Locality backfill refetch failed: \(error.localizedDescription, privacy: .public)")
            return changed
        }

        let pending = remaining
            .filter {
                needsResolution($0)
                    && hasValidCoordinate($0)
                    && !skippedNetworkIDs.contains($0.id)
            }
            .prefix(AreaResolutionTuning.backfillBatchLimit)
        guard !pending.isEmpty else { return changed }

        var resolved: [(Venue, String)] = []
        for venue in pending {
            if let name = await resolvedAreaName(for: venue, allowAddressParse: false) {
                resolved.append((venue, name))
            } else {
                skippedNetworkIDs.insert(venue.id)
            }
            try? await Task.sleep(nanoseconds: AreaResolutionTuning.backfillSpacingNanoseconds)
        }

        guard !resolved.isEmpty else { return changed }
        for (venue, name) in resolved where needsResolution(venue) {
            venue.locality = name
        }
        do {
            try context.save()
            changed = true
        } catch {
            AppLog.data.error("Locality backfill save failed: \(error.localizedDescription, privacy: .public)")
        }
        return changed
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

    private static func resolvedAreaName(for venue: Venue, allowAddressParse: Bool = true) async -> String? {
        guard needsResolution(venue), hasValidCoordinate(venue) else { return nil }
        if allowAddressParse, let parsed = AreaNameResolver.fromFormattedAddress(venue.formattedAddress) {
            return parsed
        }
        do {
            return try await reverseGeocodeAreaName(
                latitude: venue.latitude,
                longitude: venue.longitude
            )
        } catch {
            AppLog.data.info("Reverse geocode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func reverseGeocodeAreaName(latitude: Double, longitude: Double) async throws -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        let mapItems = try await request.mapItems
        guard let mapItem = mapItems.first else { return nil }
        return AreaNameResolver.preferredAreaName(from: mapItem)
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
