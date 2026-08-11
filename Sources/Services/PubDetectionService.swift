import CoreLocation
import Foundation
import Observation
import SwiftData

/// A likely pub visit in progress. Stores the full candidate so the Home
/// suggestion card can be restored after an app relaunch without a search.
private struct VisitSession: Codable, Equatable {
    var candidate: VenueCandidate
    var skipped: Bool
    var notificationSent: Bool
    var notificationScheduledAt: Date?
    var firstSeenAt: Date
    var outsideSince: Date?

    var venueLocation: CLLocation {
        CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
    }
}

@MainActor
@Observable
final class PubDetectionService {
    private static let stateKey = "ParmaMaster.VisitSession"
    private static let notificationLogKey = "ParmaMaster.VenueNotificationLog"

    private let mapSearch: MapSearching
    private let notifier: VisitNotifying
    private let defaults: UserDefaults
    /// Injectable clock so dwell/throttle behaviour is unit-testable (T-01).
    @ObservationIgnored var now: () -> Date = { .now }

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var settings: AppSettings?
    @ObservationIgnored private var repository: (any ParmaRepositoryProtocol)?
    @ObservationIgnored private weak var locationService: LocationService?

    private var anchorLocation: CLLocation?
    private var dwellStartedAt: Date?
    private var lastSearchAt: Date?
    private var visitSession: VisitSession? {
        didSet { persistVisitIfChanged(oldValue: oldValue) }
    }
    private var metrics: DetectionMetricsStore

    var currentCandidate: VenueCandidate?
    var nearbyChoices: [VenueCandidate] = []
    var statusMessage: String?

    init(
        mapSearch: MapSearching = MapSearchService(),
        notificationService: any VisitNotifying,
        defaults: UserDefaults = .standard
    ) {
        self.mapSearch = mapSearch
        self.notifier = notificationService
        self.defaults = defaults
        self.metrics = DetectionMetricsStore(defaults: defaults)
        visitSession = defaults.data(forKey: Self.stateKey)
            .flatMap { try? JSONDecoder().decode(VisitSession.self, from: $0) }
        // The candidate card is restored lazily from the first location or
        // visit event (with an age check), not here: a session persisted days
        // ago must not resurrect a stale "Welcome to X" card at launch.
    }

    /// Wires the long-lived dependencies once at app start (audit finding
    /// A-01: the pipeline previously captured a stale snapshot of all entries
    /// in a closure that was only refreshed on scene changes).
    func configure(
        context: ModelContext,
        settings: AppSettings,
        repository: any ParmaRepositoryProtocol,
        locationService: LocationService?
    ) {
        self.context = context
        self.settings = settings
        self.repository = repository
        self.locationService = locationService
    }

    var diagnosticsSummary: String {
        metrics.summary(now: now())
    }

    func skipCurrentVisit() {
        guard var session = visitSession else { return }
        cancelPendingReminderIfNeeded(for: session)
        session.skipped = true
        visitSession = session
        currentCandidate = nil
    }

    func clearVisitState() {
        if let session = visitSession {
            cancelPendingReminderIfNeeded(for: session)
        }
        visitSession = nil
        currentCandidate = nil
        nearbyChoices = []
        anchorLocation = nil
        dwellStartedAt = nil
    }

    /// Refreshes the geofence set to the most recently logged venues so
    /// "back at a known pub" detection needs no network at all. Scans a
    /// bounded, store-sorted slice of entries rather than walking every venue
    /// relationship; `setMonitoredVenues` no-ops when the set is unchanged.
    func refreshKnownVenues() {
        guard let context, let locationService else { return }
        var descriptor = FetchDescriptor<ParmaEntry>(
            sortBy: [SortDescriptor(\.currentRatingDate, order: .reverse)]
        )
        descriptor.fetchLimit = DetectionTuning.knownVenueScanLimit
        do {
            let recentEntries = try context.fetch(descriptor)
            var seenVenueIDs = Set<UUID>()
            var monitored: [MonitoredVenue] = []
            for entry in recentEntries {
                guard let venue = entry.venue, seenVenueIDs.insert(venue.id).inserted else { continue }
                monitored.append(MonitoredVenue(id: venue.id, latitude: venue.latitude, longitude: venue.longitude))
                if monitored.count == LocationTuning.maxMonitoredVenues { break }
            }
            locationService.setMonitoredVenues(monitored)
        } catch {
            AppLog.detection.error("Known-venue refresh failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Foreground location pipeline

    func process(location: CLLocation, foregroundCheck: Bool = false) async {
        guard let settings, settings.locationUseEnabled else { return }
        metrics.recordLocationUpdate(now: now())
        discardExpiredSession()
        updateDepartureState(location)

        let insideSettledVisit = visitSession.map {
            location.distance(from: $0.venueLocation) <= DetectionTuning.departureDistance
        } ?? false
        if insideSettledVisit {
            // Fresh launch mid-visit: bring the suggestion card back without
            // waiting for the search throttle.
            restoreCandidateFromSession()
            await notifyFromSessionIfEligible()
        }

        if location.speed >= DetectionTuning.transitSpeed {
            anchorLocation = location
            dwellStartedAt = nil
            return
        }

        if let anchorLocation, location.distance(from: anchorLocation) <= DetectionTuning.dwellAnchorRadius {
            dwellStartedAt = dwellStartedAt ?? now()
        } else {
            anchorLocation = location
            dwellStartedAt = now()
        }

        let hasDwelled = dwellStartedAt.map { now().timeIntervalSince($0) >= DetectionTuning.dwellDuration } ?? false
        guard throttleExpired, foregroundCheck || hasDwelled else { return }

        // A settled visit needs no further searching (audit finding B-04): the
        // venue is known and the notification decision has been made.
        guard !insideSettledVisit else { return }

        lastSearchAt = now()
        await searchAndClassify(around: location)
    }

    // MARK: - Background events

    /// System visit events (arrival/departure). The OS has already established
    /// the dwell, so no timer gating applies beyond the search throttle.
    func processVisit(coordinate: CLLocationCoordinate2D, isArrival: Bool) async {
        guard let settings, settings.locationUseEnabled, settings.locationRemindersEnabled else { return }
        discardExpiredSession()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        guard isArrival else {
            if let session = visitSession,
               location.distance(from: session.venueLocation) <= DetectionTuning.departureDistance {
                clearVisitState()
            }
            return
        }

        if let session = visitSession,
           location.distance(from: session.venueLocation) <= DetectionTuning.departureDistance {
            restoreCandidateFromSession()
            await notifyFromSessionIfEligible()
            return
        }
        guard throttleExpired else { return }
        lastSearchAt = now()
        await searchAndClassify(around: location)
    }

    /// Geofence arrival at a venue the user has logged before: zero-network
    /// "Back at X?" reminder.
    func processKnownVenueArrival(venueID: UUID) async {
        guard let settings, settings.locationUseEnabled, settings.locationRemindersEnabled,
              let context else { return }
        discardExpiredSession()
        var descriptor = FetchDescriptor<Venue>(predicate: #Predicate { $0.id == venueID })
        descriptor.fetchLimit = 1
        guard let venue = try? context.fetch(descriptor).first else { return }
        metrics.recordGeofenceEvent(now: now())

        let candidate = VenueCandidate(
            mapItemIdentifier: venue.mapItemIdentifier,
            name: venue.name,
            formattedAddress: venue.formattedAddress,
            latitude: venue.latitude,
            longitude: venue.longitude,
            locality: venue.locality
        )
        establishVisit(for: candidate)
        guard visitSession?.skipped != true else { return }
        let existingEntry = venue.entries.max { $0.lastModifiedAt < $1.lastModifiedAt }
        await activateVisitIfEligible(candidate: candidate, existingEntry: existingEntry)
    }

    /// A geofence exit for the venue the session is anchored to ends the
    /// visit: the geofence radius sits well inside the departure distance.
    func processKnownVenueExit(venueID: UUID) {
        guard let session = visitSession, let context else { return }
        var descriptor = FetchDescriptor<Venue>(predicate: #Predicate { $0.id == venueID })
        descriptor.fetchLimit = 1
        guard let venue = try? context.fetch(descriptor).first else { return }
        let venueLocation = CLLocation(latitude: venue.latitude, longitude: venue.longitude)
        if session.venueLocation.distance(from: venueLocation) <= DetectionTuning.dwellAnchorRadius {
            clearVisitState()
        }
    }

    // MARK: - Search & classification

    private var throttleExpired: Bool {
        lastSearchAt.map { now().timeIntervalSince($0) >= DetectionTuning.searchThrottle } ?? true
    }

    private func searchAndClassify(around location: CLLocation) async {
        metrics.recordSearch(now: now())
        do {
            let candidates = try await mapSearch.nearbyPubCandidates(around: location)
            let close = candidates.filter {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                    .distance(from: location) <= DetectionTuning.candidateProximity
            }
            guard let first = close.first else {
                currentCandidate = nil
                nearbyChoices = []
                statusMessage = "No clear nearby pub was found."
                return
            }

            if close.count > 1 {
                let firstDistance = CLLocation(latitude: first.latitude, longitude: first.longitude).distance(from: location)
                let secondDistance = CLLocation(latitude: close[1].latitude, longitude: close[1].longitude).distance(from: location)
                if secondDistance - firstDistance < DetectionTuning.ambiguityMargin {
                    currentCandidate = nil
                    nearbyChoices = Array(close.prefix(DetectionTuning.maxNearbyChoices))
                    statusMessage = "Several nearby venues are plausible. Choose one when logging."
                    return
                }
            }

            nearbyChoices = []
            statusMessage = nil
            establishVisit(for: first)
            guard visitSession?.skipped != true else { return }
            let existingEntry = existingEntry(for: first)
            await activateVisitIfEligible(candidate: first, existingEntry: existingEntry)
        } catch {
            AppLog.detection.error("Nearby venue lookup failed: \(error.localizedDescription)")
            statusMessage = "Nearby venue lookup is unavailable. You can still search manually."
        }
    }

    private func existingEntry(for candidate: VenueCandidate) -> ParmaEntry? {
        guard let context, let repository else { return nil }
        return (try? repository.findExisting(for: candidate, in: context)) ?? nil
    }

    // MARK: - Notification

    private var locationSuggestionDwellDuration: TimeInterval {
        settings?.locationSuggestionDwellDuration ?? LocationSuggestionDwellOption.default.duration
    }

    private func activateVisitIfEligible(candidate: VenueCandidate, existingEntry: ParmaEntry?) async {
        guard let session = visitSession, session.candidate.id == candidate.id, !session.skipped else { return }
        let dwellRemaining = locationSuggestionDwellDuration - now().timeIntervalSince(session.firstSeenAt)
        guard dwellRemaining <= 0 else {
            currentCandidate = nil
            await notifyIfAppropriate(for: candidate, existingEntry: existingEntry, delay: dwellRemaining)
            return
        }
        currentCandidate = candidate
        await notifyIfAppropriate(for: candidate, existingEntry: existingEntry, delay: 0)
    }

    private func notifyFromSessionIfEligible() async {
        guard let session = visitSession, !session.skipped else { return }
        let existingEntry = existingEntry(for: session.candidate)
        await activateVisitIfEligible(candidate: session.candidate, existingEntry: existingEntry)
    }

    private func notifyIfAppropriate(
        for venue: VenueCandidate,
        existingEntry: ParmaEntry?,
        delay: TimeInterval
    ) async {
        guard let settings, settings.locationRemindersEnabled,
              visitSession?.notificationSent != true,
              notifier.authorizationStatus == .authorized
        else { return }

        // Per-venue cooldown so a brief walk away and back does not re-ping
        // (audit finding B-08).
        if let lastNotified = notificationLog[venue.id],
           now().timeIntervalSince(lastNotified) < DetectionTuning.venueNotificationCooldown {
            markNotificationHandled()
            return
        }

        do {
            let scheduleDelay = max(delay, 0)
            try await notifier.scheduleVisitReminder(venue: venue, existingEntry: existingEntry, delay: scheduleDelay)
            recordNotification(for: venue.id)
            markNotificationHandled(scheduledAt: scheduleDelay > 0 ? now() : nil)
        } catch {
            AppLog.notifications.error("Visit reminder failed: \(error.localizedDescription)")
        }
    }

    private func markNotificationHandled(scheduledAt: Date? = nil) {
        guard var session = visitSession, !session.notificationSent else { return }
        session.notificationSent = true
        session.notificationScheduledAt = scheduledAt
        visitSession = session
    }

    private var notificationLog: [String: Date] {
        (defaults.dictionary(forKey: Self.notificationLogKey) as? [String: Date]) ?? [:]
    }

    private func recordNotification(for venueID: String) {
        var log = notificationLog.filter {
            now().timeIntervalSince($0.value) < DetectionTuning.notificationLogRetention
        }
        log[venueID] = now()
        defaults.set(log, forKey: Self.notificationLogKey)
    }

    // MARK: - Visit session state

    private func establishVisit(for venue: VenueCandidate) {
        if visitSession?.candidate.id != venue.id {
            visitSession = VisitSession(
                candidate: venue,
                skipped: false,
                notificationSent: false,
                notificationScheduledAt: nil,
                firstSeenAt: now(),
                outsideSince: nil
            )
        }
    }

    private func restoreCandidateFromSession() {
        discardExpiredSession()
        guard let session = visitSession, !session.skipped, currentCandidate == nil,
              now().timeIntervalSince(session.firstSeenAt) >= locationSuggestionDwellDuration else { return }
        currentCandidate = session.candidate
    }

    private func discardExpiredSession() {
        guard let session = visitSession,
              now().timeIntervalSince(session.firstSeenAt) >= DetectionTuning.visitSessionMaxAge else { return }
        clearVisitState()
    }

    private func updateDepartureState(_ location: CLLocation) {
        guard var session = visitSession else { return }
        if location.distance(from: session.venueLocation) > DetectionTuning.departureDistance {
            session.outsideSince = session.outsideSince ?? now()
            if let outsideSince = session.outsideSince,
               now().timeIntervalSince(outsideSince) >= DetectionTuning.departureDuration {
                clearVisitState()
                return
            }
        } else {
            session.outsideSince = nil
        }
        visitSession = session
    }

    private func cancelPendingReminderIfNeeded(for session: VisitSession) {
        guard session.notificationScheduledAt != nil,
              now().timeIntervalSince(session.firstSeenAt) < locationSuggestionDwellDuration else { return }
        notifier.cancelVisitReminder(venueID: session.candidate.id)
        removeNotificationRecord(for: session.candidate.id)
    }

    private func removeNotificationRecord(for venueID: String) {
        var log = notificationLog
        log.removeValue(forKey: venueID)
        defaults.set(log, forKey: Self.notificationLogKey)
    }

    /// Writes only when the session materially changed (audit finding B-03:
    /// this previously wrote a JSON blob to UserDefaults on every location
    /// update while a session existed).
    private func persistVisitIfChanged(oldValue: VisitSession?) {
        guard visitSession != oldValue else { return }
        guard let visitSession, let data = try? JSONEncoder().encode(visitSession) else {
            defaults.removeObject(forKey: Self.stateKey)
            return
        }
        defaults.set(data, forKey: Self.stateKey)
    }
}

// MARK: - Diagnostics counters (audit finding T-03)

/// Daily counters for validating battery behaviour in the field, surfaced in
/// Behaviour settings.
private struct DetectionMetricsStore {
    private static let key = "ParmaMaster.DetectionMetrics"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    mutating func recordLocationUpdate(now: Date) {
        bump("updates", now: now)
    }

    mutating func recordSearch(now: Date) {
        bump("searches", now: now)
    }

    mutating func recordGeofenceEvent(now: Date) {
        bump("geofence", now: now)
    }

    func summary(now: Date) -> String {
        let counters = current(now: now)
        let updates = counters["updates"] as? Int ?? 0
        let searches = counters["searches"] as? Int ?? 0
        let geofence = counters["geofence"] as? Int ?? 0
        return "Today: \(updates) location updates, \(searches) venue searches, \(geofence) saved-venue arrivals."
    }

    private func dayStamp(for date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }

    private func current(now: Date) -> [String: Any] {
        let stored = defaults.dictionary(forKey: Self.key) ?? [:]
        guard stored["day"] as? String == dayStamp(for: now) else {
            return ["day": dayStamp(for: now)]
        }
        return stored
    }

    private mutating func bump(_ counter: String, now: Date) {
        var counters = current(now: now)
        counters[counter] = (counters[counter] as? Int ?? 0) + 1
        defaults.set(counters, forKey: Self.key)
    }
}
