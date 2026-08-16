import CoreLocation
import SwiftUI
import UserNotifications

struct BehaviourSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LocationService.self) private var locationService
    @Environment(NotificationService.self) private var notificationService
    @Environment(PubDetectionService.self) private var pubDetection
    @State private var showAlwaysExplanation = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Enable Location Use", isOn: Binding(
                    get: { settings.locationUseEnabled },
                    set: { enabled in
                        settings.locationUseEnabled = enabled
                        if enabled {
                            locationService.requestAlwaysAuthorization()
                        } else {
                            settings.locationRemindersEnabled = false
                        }
                        // RootView reapplies the location plan on these
                        // settings changes; no direct start/stop needed here.
                    }
                ))

                LabeledContent("Permission", value: locationStatusText)

                if settings.locationUseEnabled {
                    Toggle("Location-Based Reminders", isOn: Binding(
                        get: { settings.locationRemindersEnabled },
                        set: { enabled in
                            if enabled { showAlwaysExplanation = true }
                            else { settings.locationRemindersEnabled = false }
                        }
                    ))
                }

                if settings.locationRemindersEnabled,
                   locationService.authorizationStatus != .authorizedAlways {
                    Label(
                        "Choose “Always” in iOS Settings for reminders to work in the background.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }

                if settings.locationRemindersEnabled {
                    Picker("Remind after", selection: $settings.locationReminderDelayMinutes) {
                        ForEach(LocationReminderDelay.allCases) { delay in
                            Text(delay.displayName).tag(delay.rawValue)
                        }
                    }
                }

                if locationService.authorizationStatus == .denied
                    || locationService.authorizationStatus == .restricted
                    || (settings.locationRemindersEnabled && locationService.authorizationStatus != .authorizedAlways) {
                    Button("Open iOS Settings", systemImage: "gear") { openSystemSettings() }
                }
            } header: {
                Text("Location")
            } footer: {
                Text("Parma Master uses your location to find pubs and sends a friendly reminder after you have stayed for the selected time. Choose “Always” so reminders still work when the app is closed.\n\n\(pubDetection.diagnosticsSummary)")
            }

            Section("Notifications") {
                LabeledContent("Permission", value: notificationStatusText)
                if notificationService.authorizationStatus == .denied {
                    Button("Open iOS Settings", systemImage: "gear") { openSystemSettings() }
                }
            }

            Section {
                Toggle("Suggest Re-runs", isOn: $settings.rerunSuggestionsEnabled)

                if settings.rerunSuggestionsEnabled {
                    Picker("Suggest after", selection: $settings.rerunStaleMonths) {
                        Text("3 months").tag(3)
                        Text("5 months").tag(5)
                        Text("6 months").tag(6)
                        Text("12 months").tag(12)
                    }

                    Picker("Hide dismissed for", selection: $settings.rerunHideMonths) {
                        Text("1 month").tag(1)
                        Text("2 months").tag(2)
                        Text("3 months").tag(3)
                    }
                }
            } header: {
                Text("Home suggestions")
            } footer: {
                Text("When enabled, Home may suggest a place you haven’t logged recently. Dismissing or logging that place hides the card for the chosen period. The suggestion yields to a location welcome card when one is active.")
            }

            Section("Onboarding") {
                Button("Replay Onboarding", systemImage: "play.circle") {
                    settings.hasCompletedOnboarding = false
                }
            }
        }
        .brandedNavigationTitle("Behaviour")
        .task { await notificationService.refreshStatus() }
        .confirmationDialog(
            "Enable background reminders?",
            isPresented: $showAlwaysExplanation,
            titleVisibility: .visible
        ) {
            Button("Continue") { enableReminders() }
            Button("Not Now", role: .cancel) { settings.locationRemindersEnabled = false }
        } message: {
            Text("Parma Master can nudge you to log a parma when you arrive at a pub. Choose “Always” when iOS asks so reminders work even when the app is closed.")
        }
    }

    private var locationStatusText: String {
        switch locationService.authorizationStatus {
        case .notDetermined: "Not requested"
        case .restricted: "Restricted"
        case .denied: "Denied"
        case .authorizedWhenInUse: "While Using"
        case .authorizedAlways: "Always"
        @unknown default: "Unknown"
        }
    }

    private var notificationStatusText: String {
        switch notificationService.authorizationStatus {
        case .notDetermined: "Not requested"
        case .denied: "Denied"
        case .authorized: "Allowed"
        case .provisional: "Provisional"
        case .ephemeral: "Temporary"
        @unknown default: "Unknown"
        }
    }

    private func enableReminders() {
        Task {
            locationService.requestAlwaysAuthorization()
            let allowed = await notificationService.requestAuthorization()
            settings.locationRemindersEnabled = allowed
            // RootView reapplies the location plan when the setting or the
            // authorization status changes, arming visit monitoring and
            // geofences only once Always is actually granted.
        }
    }

    private func openSystemSettings() {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
    }
}
