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
