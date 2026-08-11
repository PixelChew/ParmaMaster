import SwiftData
import SwiftUI

@main
struct ParmaMasterApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer
    @State private var settings: AppSettings
    @State private var currentUser: CurrentUserProfile
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
        modelContainer = try! ModelContainer(
            for: Schema(versionedSchema: ParmaSchemaV3.self),
            migrationPlan: ParmaMigrationPlan.self
        )
        let notificationService = NotificationService()
        _settings = State(initialValue: AppSettings())
        _currentUser = State(initialValue: CurrentUserProfile())
        _homeGreetingSession = State(initialValue: HomeGreetingSession())
        _repository = State(initialValue: LocalParmaRepository())
        _router = State(initialValue: AppRouter())
        _photoStore = State(initialValue: PhotoStore())
        _backupService = State(initialValue: BackupService())
        _locationService = State(initialValue: LocationService())
        _notificationService = State(initialValue: notificationService)
        _pubDetectionService = State(initialValue: PubDetectionService(notificationService: notificationService))
        _rerunSuggestionService = State(initialValue: RerunSuggestionService())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(modelContainer)
                .environment(settings)
                .environment(currentUser)
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
