import CoreLocation
import Foundation
import Observation

/// A venue the background monitor should watch with a geofence.
struct MonitoredVenue: Equatable, Sendable {
    let id: UUID
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Wraps `CLLocationManager` behind two power modes:
///
/// - **Foreground continuous updates** while the app is on screen, feeding the
///   dwell detector and venue pick-up.
/// - **Background monitoring** via `startMonitoringVisits()` plus geofences
///   around known venues. Both are system-batched, allow full app suspension,
///   relaunch the app on events, and need no `UIBackgroundModes` entry.
///
/// The previous implementation held `startUpdatingLocation()` continuously in
/// the background (audit finding B-01), which was the root cause of the
/// reported battery drain and also silently died after an automatic pause
/// (B-05). Continuous updates are now foreground-only by construction.
@MainActor
@Observable
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private enum SessionLevel {
        case whenInUse
        case always
    }

    private static let venueRegionPrefix = "venue-"

    private let manager = CLLocationManager()
    private var serviceSession: CLServiceSession?
    private var sessionLevel: SessionLevel?
    private var oneShotWaiters: [CheckedContinuation<CLLocation, Error>] = []
    private var oneShotTimeoutTask: Task<Void, Never>?
    private var monitoringRequested = false
    private var foregroundUpdatesActive = false
    private var monitoredVenues: [MonitoredVenue] = []

    var authorizationStatus: CLAuthorizationStatus
    var latestLocation: CLLocation?
    var lastErrorMessage: String?

    @ObservationIgnored var onLocationUpdate: ((CLLocation) -> Void)?
    /// Coordinate of the visit and whether it is an arrival (`true`) or departure.
    @ObservationIgnored var onVisitEvent: ((CLLocationCoordinate2D, Bool) -> Void)?
    @ObservationIgnored var onKnownVenueEntry: ((UUID) -> Void)?
    @ObservationIgnored var onKnownVenueExit: ((UUID) -> Void)?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = LocationTuning.desiredAccuracy
        manager.distanceFilter = LocationTuning.distanceFilter
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = true
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - Authorization

    /// The app asks for Always access directly. From `.notDetermined` iOS
    /// shows its standard prompt and grants provisional Always on approval;
    /// from When-In-Use it shows the upgrade prompt once. Monitoring itself is
    /// armed by `apply(_:)` only when Always is actually in effect.
    func requestAlwaysAuthorization() {
        guard authorizationStatus != .denied, authorizationStatus != .restricted else { return }
        updateSession(.always)
        manager.requestAlwaysAuthorization()
    }

    // MARK: - Activity plan

    /// Applies the desired activity plan idempotently: repeated calls with the
    /// same plan make no state changes (audit finding A-02).
    func apply(_ plan: LocationActivityPlan) {
        if plan.backgroundMonitoring {
            startBackgroundMonitoring()
        } else {
            stopBackgroundMonitoring()
        }
        if plan.continuousForegroundUpdates {
            startForegroundUpdates()
        } else {
            stopForegroundUpdates()
        }
        if plan == .stopped {
            updateSession(nil)
        } else if !plan.backgroundMonitoring {
            // Don't keep holding an Always session once monitoring is off.
            updateSession(.whenInUse)
        }
    }

    func startForegroundUpdates() {
        if sessionLevel == nil {
            updateSession(monitoringRequested ? .always : .whenInUse)
        }
        guard !foregroundUpdatesActive else { return }
        foregroundUpdatesActive = true
        manager.startUpdatingLocation()
    }

    func stopForegroundUpdates() {
        guard foregroundUpdatesActive else { return }
        foregroundUpdatesActive = false
        manager.stopUpdatingLocation()
    }

    private func startBackgroundMonitoring() {
        monitoringRequested = true
        updateSession(.always)
        guard authorizationStatus == .authorizedAlways else { return }
        manager.startMonitoringVisits()
        syncVenueRegions()
    }

    private func stopBackgroundMonitoring() {
        guard monitoringRequested else { return }
        monitoringRequested = false
        manager.stopMonitoringVisits()
        removeAllVenueRegions()
    }

    /// Stops everything. Used by app reset.
    func stopUpdates() {
        stopForegroundUpdates()
        stopBackgroundMonitoring()
        updateSession(nil)
    }

    // MARK: - Known-venue geofences

    func setMonitoredVenues(_ venues: [MonitoredVenue]) {
        let capped = Array(venues.prefix(LocationTuning.maxMonitoredVenues))
        guard capped != monitoredVenues else { return }
        monitoredVenues = capped
        syncVenueRegions()
    }

    private func syncVenueRegions() {
        guard monitoringRequested, authorizationStatus == .authorizedAlways else { return }
        let desired = Dictionary(
            uniqueKeysWithValues: monitoredVenues.map { (Self.venueRegionPrefix + $0.id.uuidString, $0) }
        )
        let current = manager.monitoredRegions.filter { $0.identifier.hasPrefix(Self.venueRegionPrefix) }
        for region in current where desired[region.identifier] == nil {
            manager.stopMonitoring(for: region)
        }
        let existing = Set(current.map(\.identifier))
        for (identifier, venue) in desired where !existing.contains(identifier) {
            let region = CLCircularRegion(
                center: venue.coordinate,
                radius: LocationTuning.knownVenueGeofenceRadius,
                identifier: identifier
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }

    private func removeAllVenueRegions() {
        for region in manager.monitoredRegions where region.identifier.hasPrefix(Self.venueRegionPrefix) {
            manager.stopMonitoring(for: region)
        }
    }

    private static func venueID(fromRegionIdentifier identifier: String) -> UUID? {
        guard identifier.hasPrefix(venueRegionPrefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(venueRegionPrefix.count)))
    }

    // MARK: - Service session

    private func updateSession(_ level: SessionLevel?) {
        guard level != sessionLevel else { return }
        serviceSession?.invalidate()
        sessionLevel = level
        switch level {
        case .whenInUse:
            serviceSession = CLServiceSession(authorization: .whenInUse)
        case .always:
            serviceSession = CLServiceSession(authorization: .always)
        case nil:
            serviceSession = nil
        }
    }

    // MARK: - One-shot location

    /// Single-flight one-shot fix with a timeout, so concurrent callers share
    /// one request and nobody awaits forever (audit finding A-03).
    func currentLocation() async throws -> CLLocation {
        if let latestLocation,
           Date.now.timeIntervalSince(latestLocation.timestamp) < LocationTuning.cachedFixMaxAge {
            return latestLocation
        }
        return try await withCheckedThrowingContinuation { continuation in
            oneShotWaiters.append(continuation)
            guard oneShotWaiters.count == 1 else { return }
            manager.requestLocation()
            oneShotTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(LocationTuning.oneShotTimeout))
                guard !Task.isCancelled else { return }
                self?.finishOneShot(with: .failure(CLError(.locationUnknown)))
            }
        }
    }

    private func finishOneShot(with result: Result<CLLocation, Error>) {
        oneShotTimeoutTask?.cancel()
        oneShotTimeoutTask = nil
        let waiters = oneShotWaiters
        oneShotWaiters = []
        for waiter in waiters {
            waiter.resume(with: result)
        }
    }

    private func receive(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= LocationTuning.accuracyAcceptanceLimit else { return }
        latestLocation = location
        lastErrorMessage = nil
        if !oneShotWaiters.isEmpty {
            finishOneShot(with: .success(location))
        }
        onLocationUpdate?(location)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways, monitoringRequested {
            manager.startMonitoringVisits()
            syncVenueRegions()
        }
        if authorizationStatus == .denied || authorizationStatus == .restricted {
            lastErrorMessage = "Location access is off. You can still search for venues manually."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last { receive(location) }
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let isArrival = visit.departureDate == .distantFuture
        AppLog.location.info("Visit event received, arrival: \(isArrival)")
        onVisitEvent?(visit.coordinate, isArrival)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let venueID = Self.venueID(fromRegionIdentifier: region.identifier) else { return }
        AppLog.location.info("Known-venue geofence entered")
        onKnownVenueEntry?(venueID)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let venueID = Self.venueID(fromRegionIdentifier: region.identifier) else { return }
        onKnownVenueExit?(venueID)
    }

    func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        AppLog.location.error("Region monitoring failed: \(error.localizedDescription)")
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        // Foreground-only updates can pause while stationary; note it so a
        // stalled pipeline is diagnosable. The next plan application restarts.
        AppLog.location.info("Continuous updates paused by the system")
        foregroundUpdatesActive = false
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if !oneShotWaiters.isEmpty {
            finishOneShot(with: .failure(error))
        }
        lastErrorMessage = "Your location could not be determined."
    }
}

// MARK: - Activity policy

/// What the location subsystem should be doing for a given app state.
struct LocationActivityPlan: Equatable {
    /// Continuous updates while the app is on screen.
    var continuousForegroundUpdates: Bool
    /// Visit + known-venue geofence monitoring for background reminders.
    var backgroundMonitoring: Bool

    static let stopped = LocationActivityPlan(continuousForegroundUpdates: false, backgroundMonitoring: false)
}

enum LocationActivityPolicy {
    static func plan(
        locationUseEnabled: Bool,
        remindersEnabled: Bool,
        authorizationStatus: CLAuthorizationStatus,
        sceneIsActive: Bool
    ) -> LocationActivityPlan {
        guard locationUseEnabled else { return .stopped }
        return LocationActivityPlan(
            continuousForegroundUpdates: sceneIsActive,
            backgroundMonitoring: remindersEnabled && authorizationStatus == .authorizedAlways
        )
    }
}
