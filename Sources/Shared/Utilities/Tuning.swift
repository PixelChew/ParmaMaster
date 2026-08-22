import CoreLocation
import Foundation

/// Central home for behavioural policy constants that were previously
/// scattered inline across services (audit finding H-01).

enum LocationTuning {
    /// Delivery granularity for foreground continuous updates.
    static let distanceFilter: CLLocationDistance = 75
    static let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters
    /// Fixes worse than this are discarded outright.
    static let accuracyAcceptanceLimit: CLLocationAccuracy = 250
    /// How long a cached fix satisfies `currentLocation()` without a new request.
    static let cachedFixMaxAge: TimeInterval = 60
    /// One-shot `currentLocation()` gives up after this long.
    static let oneShotTimeout: TimeInterval = 15
    /// Geofence radius around known venues for background arrival detection.
    static let knownVenueGeofenceRadius: CLLocationDistance = 120
    /// iOS enforces a 20-region cap per app; leave headroom for future use.
    static let maxMonitoredVenues = 18
}

enum DetectionTuning {
    /// Minimum interval between venue search fan-outs.
    static let searchThrottle: TimeInterval = 15 * 60
    /// Distance from the visit venue that starts the departure countdown.
    static let departureDistance: CLLocationDistance = 250
    /// Time beyond `departureDistance` before the visit is considered over.
    static let departureDuration: TimeInterval = 5 * 60
    /// Speeds at or above this reset the dwell anchor (clearly in transit).
    static let transitSpeed: CLLocationSpeed = 2.5
    /// Radius around the anchor that still counts as dwelling.
    static let dwellAnchorRadius: CLLocationDistance = 100
    /// Candidates farther than this from the user are ignored.
    static let candidateProximity: CLLocationDistance = 160
    /// Two candidates closer together than this are ambiguous.
    static let ambiguityMargin: CLLocationDistance = 35
    /// Maximum ambiguous choices surfaced to the user.
    static let maxNearbyChoices = 4
    /// Search queries fanned out per venue lookup.
    static let searchQueries = ["pub", "brewery", "nightlife"]
    /// Square search region edge, metres.
    static let searchRegionSpan: CLLocationDistance = 450
    /// Do not re-notify the same venue within this window.
    static let venueNotificationCooldown: TimeInterval = 24 * 60 * 60
    /// A persisted visit session older than this is stale (e.g. the app was
    /// terminated mid-visit and no departure was ever observed) and must not
    /// resurrect the suggestion card.
    static let visitSessionMaxAge: TimeInterval = 8 * 60 * 60
    /// Entries scanned (most recent first) when choosing venues to geofence.
    static let knownVenueScanLimit = 120
    /// Prune notification-log records older than this.
    static let notificationLogRetention: TimeInterval = 7 * 24 * 60 * 60
}

enum AreaResolutionTuning {
    /// Max venues reverse-geocoded per backfill pass (app launch). Offline
    /// address parsing is unbounded and runs first.
    static let backfillBatchLimit = 24
    /// Pause between geocode requests to avoid hammering MapKit.
    static let backfillSpacingNanoseconds: UInt64 = 250_000_000
}

enum PhotoTuning {
    /// Longest edge stored on disk.
    static let maxStoredDimension: CGFloat = 1_920
    static let jpegCompressionQuality: CGFloat = 0.78
    /// Longest edge (pixels) for list-row thumbnails.
    static let thumbnailPixelSize: CGFloat = 480
}

enum InsightsTuning {
    /// The launch preload uses a fixed phone-sized canvas; the card requests an
    /// exact-width replacement after SwiftUI supplies its real layout width.
    static let preloadedMapWidth: CGFloat = 400
    static let mapCardHeight: CGFloat = 280
    /// Caps how many score labels the interactive map shows unclustered.
    static let densePinThreshold = 50
    /// Dots drawn onto the static Insights map snapshot.
    static let snapshotPinLimit = 40
    /// Maximum latitude/longitude span for the Insights map card. Fitting every
    /// pin nationwide pulled a continent of MapKit tiles and froze first open.
    static let maxCardSpan: CLLocationDegrees = 0.35
    static let maxDisplayedStandouts = 8
    static let maxDisplayedPerfectScores = 12
}

enum BackupTuning {
    /// Minimum interval between automatic backups.
    static let minimumAutomaticInterval: TimeInterval = 5 * 60
    /// Coalescing window after a data change before an automatic backup runs.
    static let dirtyDebounce: Duration = .seconds(30)
    static let backupFilename = "Parma Master.parmabackup"
    static let temporaryFilename = ".Parma Master.parmabackup.tmp"
}
