import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(PhotoStore.self) private var photoStore
    @Environment(BackupService.self) private var backupService
    @Environment(LocationService.self) private var locationService
    @Environment(NotificationService.self) private var notificationService
    @Environment(PubDetectionService.self) private var pubDetection
    @Query private var entries: [ParmaEntry]

    var body: some View {
        @Bindable var router = router

        Group {
            if settings.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingFlowView()
            }
        }
        .animation(.snappy, value: settings.hasCompletedOnboarding)
        .sheet(item: $router.loggerRequest) { request in
            LoggerView(request: request)
        }
        .sheet(item: $router.presentedDetails) { entry in
            NavigationStack {
                ParmaDetailsView(entry: entry)
            }
        }
        .sheet(isPresented: $router.showingAreasList) {
            AreasListView()
        }
        .task {
            backupService.configure(context: modelContext, settings: settings, photoStore: photoStore)
            await notificationService.refreshStatus()
            configureLocationPipeline(sceneIsActive: scenePhase == .active)
            await AreaResolutionService.backfillMissingLocalities(in: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                configureLocationPipeline(sceneIsActive: true)
                Task { await runForegroundVenueCheck() }
            case .background:
                configureLocationPipeline(sceneIsActive: false)
                Task { await backupService.performAutomaticBackupIfNeeded() }
            default:
                break
            }
        }
        .onChange(of: settings.locationUseEnabled) { _, _ in
            configureLocationPipeline(sceneIsActive: scenePhase == .active)
        }
        .onChange(of: settings.locationRemindersEnabled) { _, _ in
            configureLocationPipeline(sceneIsActive: scenePhase == .active)
        }
        .onReceive(NotificationCenter.default.publisher(for: .parmaNotificationDeepLink)) { notification in
            handleDeepLink(notification.userInfo ?? [:])
        }
    }

    private func configureLocationPipeline(sceneIsActive: Bool) {
        locationService.onLocationUpdate = { location in
            Task { @MainActor in
                await pubDetection.process(location: location, entries: entries, settings: settings)
            }
        }
        switch LocationActivityPolicy.mode(
            locationUseEnabled: settings.locationUseEnabled,
            remindersEnabled: settings.locationRemindersEnabled,
            authorizationStatus: locationService.authorizationStatus,
            sceneIsActive: sceneIsActive
        ) {
        case .stopped:
            locationService.stopUpdates()
        case .foreground:
            locationService.startForegroundUpdates()
        case .background:
            locationService.requestAlwaysAndStartBackgroundUpdates()
        }
    }

    private func runForegroundVenueCheck() async {
        guard settings.hasCompletedOnboarding, settings.locationUseEnabled else { return }
        do {
            let location = try await locationService.currentLocation()
            await pubDetection.process(
                location: location,
                entries: entries,
                settings: settings,
                foregroundCheck: true
            )
        } catch {
            // The Home and Settings views expose the degraded location state.
        }
    }

    private func handleDeepLink(_ userInfo: [AnyHashable: Any]) {
        if let idString = userInfo["entryID"] as? String,
           let id = UUID(uuidString: idString),
           let entry = entries.first(where: { $0.id == id }) {
            router.openLogEntry(entry)
            return
        }

        if let encoded = userInfo["venue"] as? String,
           let data = Data(base64Encoded: encoded),
           let venue = try? JSONDecoder().decode(VenueCandidate.self, from: data) {
            router.openHomeLogger(venue: venue)
        }
    }
}

private struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @State private var homeRootID = UUID()
    @State private var logRootID = UUID()
    @State private var insightsRootID = UUID()
    @State private var settingsRootID = UUID()
    @State private var searchRootID = UUID()

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeView()
                    .id(homeRootID)
                    .modifier(TabEntranceEffect())
            }
            Tab("Parma Log", systemImage: "book.pages", value: .log) {
                ParmaLogView()
                    .id(logRootID)
                    .modifier(TabEntranceEffect())
            }
            Tab("Insights", systemImage: "chart.bar.xaxis", value: .insights) {
                InsightsView()
                    .id(insightsRootID)
                    .modifier(TabEntranceEffect())
            }
            Tab("Settings", systemImage: "gear", value: .settings) {
                SettingsView()
                    .id(settingsRootID)
                    .modifier(TabEntranceEffect())
            }
            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                SearchEntriesView()
                    .id(searchRootID)
                    .modifier(TabEntranceEffect())
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // TabView never animates programmatic selection changes (e.g. Home card
        // taps into Insights or the Parma Log), so the incoming tab animates its
        // own content in via TabEntranceEffect instead.
        .onChange(of: router.selectedTab) { previousTab, selectedTab in
            guard previousTab != selectedTab else { return }
            // Delay remounting the previous tab so nested navigation pops after the
            // tab bar has settled — resetting `.id` immediately makes switches feel abrupt.
            Task { @MainActor in
                try? await Task.sleep(for: BrandMotion.tabTransitionDelay)
                guard router.selectedTab == selectedTab else { return }
                switch previousTab {
                case .home: homeRootID = UUID()
                case .log: logRootID = UUID()
                case .insights: insightsRootID = UUID()
                case .settings: settingsRootID = UUID()
                case .search: searchRootID = UUID()
                }
            }
        }
    }
}

/// Fades and rises tab content in whenever its tab becomes visible.
/// `onAppear`/`onDisappear` fire on every tab selection change, so this runs
/// for both tab-bar taps and programmatic switches from Home cards.
private struct TabEntranceEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSettled = false

    func body(content: Content) -> some View {
        content
            .opacity(isSettled ? 1 : 0)
            .offset(y: isSettled ? 0 : 12)
            .onAppear {
                if reduceMotion {
                    isSettled = true
                } else {
                    withAnimation(BrandMotion.standard) { isSettled = true }
                }
            }
            .onDisappear { isSettled = false }
    }
}
