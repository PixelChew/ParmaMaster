import CoreLocation
import Foundation
import Observation

private struct VisitSession: Codable {
    var venueID: String
    var latitude: Double
    var longitude: Double
    var skipped: Bool
    var notificationSent: Bool
    var firstSeenAt: Date
    var outsideSince: Date?
}

@MainActor
@Observable
final class PubDetectionService {
    private static let stateKey = "ParmaMaster.VisitSession"
    private static let searchThrottle: TimeInterval = 15 * 60
    private static let dwellDuration: TimeInterval = 8 * 60
    private static let departureDistance: CLLocationDistance = 250
    private static let departureDuration: TimeInterval = 5 * 60

    private let mapSearch: MapSearching
    private let notificationService: NotificationService
    private let defaults: UserDefaults
    private var anchorLocation: CLLocation?
    private var dwellStartedAt: Date?
    private var lastSearchAt: Date?
    private var visitSession: VisitSession?

    var currentCandidate: VenueCandidate?
    var nearbyChoices: [VenueCandidate] = []
    var statusMessage: String?

    init(
        mapSearch: MapSearching = MapSearchService(),
        notificationService: NotificationService,
        defaults: UserDefaults = .standard
    ) {
        self.mapSearch = mapSearch
        self.notificationService = notificationService
        self.defaults = defaults
        visitSession = defaults.data(forKey: Self.stateKey)
            .flatMap { try? JSONDecoder().decode(VisitSession.self, from: $0) }
    }

    func skipCurrentVisit() {
        guard var visitSession else { return }
        visitSession.skipped = true
        self.visitSession = visitSession
        currentCandidate = nil
        persistVisit()
    }

    func clearVisitState() {
        visitSession = nil
        currentCandidate = nil
        nearbyChoices = []
        anchorLocation = nil
        dwellStartedAt = nil
        defaults.removeObject(forKey: Self.stateKey)
    }

    func process(
        location: CLLocation,
        entries: [ParmaEntry],
        settings: AppSettings,
        foregroundCheck: Bool = false
    ) async {
        guard settings.locationUseEnabled else { return }
        updateDepartureState(location)

        if location.speed >= 2.5 {
            anchorLocation = location
            dwellStartedAt = nil
            return
        }

        if let anchorLocation, location.distance(from: anchorLocation) <= 100 {
            dwellStartedAt = dwellStartedAt ?? .now
        } else {
            anchorLocation = location
            dwellStartedAt = .now
        }

        let hasDwelled = dwellStartedAt.map { Date.now.timeIntervalSince($0) >= Self.dwellDuration } ?? false
        let throttleExpired = lastSearchAt.map { Date.now.timeIntervalSince($0) >= Self.searchThrottle } ?? true
        guard throttleExpired, foregroundCheck || hasDwelled else { return }
        lastSearchAt = .now

        do {
            let candidates = try await mapSearch.nearbyPubCandidates(around: location)
            let close = candidates.filter {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: location) <= 160
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
                if secondDistance - firstDistance < 35 {
                    currentCandidate = nil
                    nearbyChoices = Array(close.prefix(4))
                    statusMessage = "Several nearby venues are plausible. Choose one when logging."
                    return
                }
            }

            nearbyChoices = []
            statusMessage = nil
            establishVisit(for: first)
            guard visitSession?.skipped != true else { return }
            currentCandidate = first

            if settings.locationRemindersEnabled,
               visitSession?.notificationSent != true,
               notificationService.authorizationStatus == .authorized {
                let existing = EntryRepository.findExisting(for: first, in: entries)
                try await notificationService.scheduleVisitReminder(venue: first, existingEntry: existing)
                visitSession?.notificationSent = true
                persistVisit()
            }
        } catch {
            statusMessage = "Nearby venue lookup is unavailable. You can still search manually."
        }
    }

    private func establishVisit(for venue: VenueCandidate) {
        if visitSession?.venueID != venue.id {
            visitSession = VisitSession(
                venueID: venue.id,
                latitude: venue.latitude,
                longitude: venue.longitude,
                skipped: false,
                notificationSent: false,
                firstSeenAt: .now,
                outsideSince: nil
            )
            persistVisit()
        }
    }

    private func updateDepartureState(_ location: CLLocation) {
        guard var visitSession else { return }
        let venueLocation = CLLocation(latitude: visitSession.latitude, longitude: visitSession.longitude)
        if location.distance(from: venueLocation) > Self.departureDistance {
            visitSession.outsideSince = visitSession.outsideSince ?? .now
            if let outsideSince = visitSession.outsideSince,
               Date.now.timeIntervalSince(outsideSince) >= Self.departureDuration {
                clearVisitState()
                return
            }
        } else {
            visitSession.outsideSince = nil
        }
        self.visitSession = visitSession
        persistVisit()
    }

    private func persistVisit() {
        guard let visitSession, let data = try? JSONEncoder().encode(visitSession) else {
            defaults.removeObject(forKey: Self.stateKey)
            return
        }
        defaults.set(data, forKey: Self.stateKey)
    }
}
