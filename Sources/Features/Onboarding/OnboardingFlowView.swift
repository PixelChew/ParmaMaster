import AVFoundation
import Photos
import SwiftUI
import UserNotifications

struct OnboardingFlowView: View {
    @Environment(AppSettings.self) private var settings
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TabView(selection: $page) {
            WelcomeView {
                withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.86)) {
                    page = 1
                }
            }
            .tag(0)

            PermissionsExplanationView {
                settings.hasCompletedOnboarding = true
            }
            .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
    }
}

private struct WelcomeView: View {
    let continueAction: () -> Void

    var body: some View {
        ZStack {
            AspectFillImage(image: UIImage(named: "OnboardingHero") ?? UIImage())
                .ignoresSafeArea()
                .scaleEffect(1.25)
                .blur(radius: 4, opaque: true)
                .overlay(Color.black.opacity(0.18).ignoresSafeArea())

            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 0) {
                    Text("Welcome to")
                        .font(BrandStyle.displayFont(33, relativeTo: .title))
                    Text("Parma Master")
                        .font(BrandStyle.displayFont(52, relativeTo: .largeTitle))
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)

                Spacer()

                Button("Let’s go", action: continueAction)
                    .font(.title3.bold())
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint((Color(hex: BrandStyle.defaultAccentHex) ?? .orange).opacity(0.86))
                    .frame(maxWidth: 260)
                    .accessibilityHint("Shows how Parma Master uses permissions")
                Spacer()
            }
            .padding(.horizontal, BrandStyle.pagePadding)
        }
    }
}

private struct PermissionsExplanationView: View {
    let continueAction: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Environment(LocationService.self) private var locationService
    @Environment(NotificationService.self) private var notificationService
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var isRequestingMedia = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 80)
                Text("First things first.")
                    .font(BrandStyle.displayFont(41, relativeTo: .largeTitle))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 18) {
                    PermissionCard(
                        title: "Location",
                        message: "Finds the pub you are at and can remind you to log a parma later. Choose “Always” when iOS asks.",
                        symbol: "location",
                        isApproved: locationIsApproved,
                        action: requestLocation
                    )
                    PermissionCard(
                        title: "Camera & Photos",
                        message: "Snap a photo or pick one from your library when you add it to an entry.",
                        symbol: "camera",
                        isApproved: mediaIsApproved,
                        isRequesting: isRequestingMedia,
                        action: requestCameraAndPhotos
                    )
                    PermissionCard(
                        title: "Notifications",
                        message: "A friendly nudge to log your parma when it looks like you're at a pub.",
                        symbol: "bell.badge",
                        isApproved: notificationsAreApproved,
                        action: requestNotifications
                    )
                }

                Text("Parma Master asks for each permission only when you use the related feature. Everything else keeps working if you say no.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Continue", action: continueAction)
                    .font(.title3.bold())
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .frame(maxWidth: 260)
                    .padding(.top, 12)
                Spacer(minLength: 48)
            }
            .padding(.horizontal, BrandStyle.pagePadding)
        }
        .brandPageBackground()
        .task { await refreshPermissionStatuses() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshPermissionStatuses() }
        }
        // The setting follows the actual grant rather than being switched on
        // optimistically before iOS answers (audit finding UX-03).
        .onChange(of: locationService.authorizationStatus) { _, status in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                settings.locationUseEnabled = true
            }
        }
    }

    private var locationIsApproved: Bool {
        locationService.authorizationStatus == .authorizedWhenInUse
            || locationService.authorizationStatus == .authorizedAlways
    }

    private var mediaIsApproved: Bool {
        cameraStatus == .authorized && (photoStatus == .authorized || photoStatus == .limited)
    }

    private var notificationsAreApproved: Bool {
        switch notificationService.authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    private func requestLocation() {
        if locationService.authorizationStatus == .denied || locationService.authorizationStatus == .restricted {
            openSystemSettings()
            return
        }
        if locationService.authorizationStatus == .authorizedWhenInUse
            || locationService.authorizationStatus == .authorizedAlways {
            settings.locationUseEnabled = true
        }
        locationService.requestAlwaysAuthorization()
    }

    private func requestCameraAndPhotos() {
        if cameraStatus == .denied || cameraStatus == .restricted || photoStatus == .denied || photoStatus == .restricted {
            openSystemSettings()
            return
        }

        isRequestingMedia = true
        Task {
            if cameraStatus == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)

            if photoStatus == .notDetermined {
                photoStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            } else {
                photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            }
            isRequestingMedia = false
        }
    }

    private func requestNotifications() {
        if notificationService.authorizationStatus == .denied {
            openSystemSettings()
            return
        }
        Task { _ = await notificationService.requestAuthorization() }
    }

    private func refreshPermissionStatuses() async {
        locationService.refreshAuthorizationStatus()
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        await notificationService.refreshStatus()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct PermissionCard: View {
    let title: String
    let message: String
    let symbol: String
    let isApproved: Bool
    var isRequesting = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(BrandStyle.displayFont(22, relativeTo: .title3))
                        .foregroundStyle(.primary)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if isRequesting {
                    ProgressView()
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: isApproved ? "checkmark.circle.fill" : "arrow.up.forward.circle")
                        .foregroundStyle(isApproved ? Color.green : Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .brandCard(emphasised: isApproved)
        }
        .buttonStyle(.plain)
        .disabled(isRequesting)
        .accessibilityLabel("\(title), \(isApproved ? "approved" : "request permission")")
        .accessibilityHint(isApproved ? "Permission approved" : "Requests this permission from iOS")
    }
}
