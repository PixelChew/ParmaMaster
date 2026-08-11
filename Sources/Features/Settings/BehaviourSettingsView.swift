import CoreLocation
import SwiftUI
import UserNotifications

struct BehaviourSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LocationService.self) private var locationService
    @Environment(NotificationService.self) private var notificationService
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
                            locationService.requestWhenInUse()
                            locationService.startForegroundUpdates()
                        } else {
                            settings.locationRemindersEnabled = false
                            locationService.stopUpdates()
                        }
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

                if locationService.authorizationStatus == .denied || locationService.authorizationStatus == .restricted {
                    Button("Open iOS Settings", systemImage: "gear") { openSystemSettings() }
                }
            } header: {
                Text("Location")
            } footer: {
                Text("Foreground checks still work with When In Use permission. Automatic background detection is best effort and requires Always permission and Location Updates background mode.")
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
            Text("Parma Master needs Always location access to attempt low-power pub detection after you leave the app. It searches only after a likely dwell and sends local notifications; detection is not guaranteed.")
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
            locationService.requestAlwaysAndStartBackgroundUpdates()
            let allowed = await notificationService.requestAuthorization()
            settings.locationRemindersEnabled = allowed
            if !allowed {
                locationService.startForegroundUpdates()
            }
        }
    }

    private func openSystemSettings() {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
    }
}
