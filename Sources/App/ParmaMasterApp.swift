import SwiftData
import SwiftUI

@main
struct ParmaMasterApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var store: ModelContainerState
    @State private var settings: AppSettings
    @State private var homeGreetingSession: HomeGreetingSession
    @State private var repository: LocalParmaRepository
    @State private var router: AppRouter
    @State private var photoStore: PhotoStore
    @State private var backupService: BackupService
    @State private var locationService: LocationService
    @State private var notificationService: NotificationService
    @State private var pubDetectionService: PubDetectionService
    @State private var rerunSuggestionService: RerunSuggestionService

    init() {
        let store = ModelContainerState()
        let notificationService = NotificationService()
        let settings = AppSettings()
        let repository = LocalParmaRepository()
        let locationService = LocationService()
        let pubDetectionService = PubDetectionService(notificationService: notificationService)

        // Visit and geofence events can relaunch the app in the background and
        // are delivered as soon as the run loop turns — before any view's
        // `.task` runs. Wire the pipeline here so nothing is dropped.
        if let container = store.container {
            pubDetectionService.configure(
                context: container.mainContext,
                settings: settings,
                repository: repository,
                locationService: locationService
            )
        }
        locationService.onLocationUpdate = { [weak pubDetectionService] location in
            Task { @MainActor in
                await pubDetectionService?.process(location: location)
            }
        }
        locationService.onVisitEvent = { [weak pubDetectionService] coordinate, isArrival in
            Task { @MainActor in
                await pubDetectionService?.processVisit(coordinate: coordinate, isArrival: isArrival)
            }
        }
        locationService.onKnownVenueEntry = { [weak pubDetectionService] venueID in
            Task { @MainActor in
                await pubDetectionService?.processKnownVenueArrival(venueID: venueID)
            }
        }
        locationService.onKnownVenueExit = { [weak pubDetectionService] venueID in
            Task { @MainActor in
                pubDetectionService?.processKnownVenueExit(venueID: venueID)
            }
        }
        locationService.onPendingVisitExit = { [weak pubDetectionService] in
            Task { @MainActor in
                pubDetectionService?.processPendingVisitExit()
            }
        }

        _store = State(initialValue: store)
        _settings = State(initialValue: settings)
        _homeGreetingSession = State(initialValue: HomeGreetingSession())
        _repository = State(initialValue: repository)
        _router = State(initialValue: AppRouter())
        _photoStore = State(initialValue: PhotoStore())
        _backupService = State(initialValue: BackupService())
        _locationService = State(initialValue: locationService)
        _notificationService = State(initialValue: notificationService)
        _pubDetectionService = State(initialValue: pubDetectionService)
        _rerunSuggestionService = State(initialValue: RerunSuggestionService())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container = store.container {
                    RootView()
                        .modelContainer(container)
                } else {
                    StoreRecoveryView(
                        errorDescription: store.errorDescription,
                        retry: { store.attempt() },
                        reset: { store.resetStoreAndRetry() }
                    )
                }
            }
            .environment(settings)
            .environment(homeGreetingSession)
            .environment(repository)
            .environment(router)
            .environment(photoStore)
            .environment(backupService)
            .environment(locationService)
            .environment(notificationService)
            .environment(pubDetectionService)
            .environment(rerunSuggestionService)
            .tint(settings.accentColor)
            .preferredColorScheme(settings.theme.colorScheme)
        }
    }
}

/// Owns `ModelContainer` creation so a failed migration surfaces a recovery
/// screen instead of crashing at launch in a loop (audit finding H-03: the
/// previous `try!` made a bad migration an unrecoverable data lockout).
@MainActor
@Observable
final class ModelContainerState {
    private(set) var container: ModelContainer?
    private(set) var errorDescription: String?

    init() {
        attempt()
    }

    func attempt() {
        do {
            container = try ModelContainer(
                for: Schema(versionedSchema: ParmaSchemaV3.self),
                migrationPlan: ParmaMigrationPlan.self
            )
            errorDescription = nil
        } catch {
            container = nil
            errorDescription = error.localizedDescription
            AppLog.data.critical("Model container creation failed: \(error.localizedDescription)")
        }
    }

    /// Deletes the on-disk store and starts fresh. Destructive, but only
    /// reachable from an explicit user action on the recovery screen.
    func resetStoreAndRetry() {
        let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
        attempt()
    }
}

private struct StoreRecoveryView: View {
    let errorDescription: String?
    let retry: () -> Void
    let reset: () -> Void
    @State private var confirmingReset = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("Your data could not be opened")
                .font(BrandStyle.displayFont(31, relativeTo: .title))
                .multilineTextAlignment(.center)
            Text("Parma Master could not open its local database. This can happen after an interrupted update. Your backup file, if you have one, is unaffected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let errorDescription {
                Text(errorDescription)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            Button("Delete Data and Start Fresh", role: .destructive) {
                confirmingReset = true
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            Spacer()
        }
        .padding(.horizontal, BrandStyle.pagePadding)
        .confirmationDialog(
            "Delete all local data?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive, action: reset)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the unreadable local database. Restore from a backup afterwards if you have one.")
        }
    }
}
